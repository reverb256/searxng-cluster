{
  pkgs,
  config,
  lib,
  ...
}:
{
  config.kubernetes.objects = {
    none.Namespace.search = {
      metadata.labels = {
        name = "search";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    search.Secret.searxng-secret = {
      type = "Opaque";
      stringData = {
        "secret-key" = "REDACTED_SEARXNG_SECRET_KEY";
      };
    };

    search.ConfigMap.searxng-config = {
      data."settings.yml" = ''
        server:
          port: 7777
          secret_key: "@SEARXNG_SECRET_KEY@"
          limiter: false
          image_proxy: true
        search:
          formats:
            - html
            - json
            - csv
            - rss
        ui:
          infinite_scroll: false
          static_use_hash: true
      '';
    };

    search.ConfigMap.searxng-settings-production = {
      data."settings.yml" = ''
        server:
          limiter: false
          secret_key: "REDACTED_SEARXNG_SECRET_KEY"
          methods: []
          port: 8888
          bind_address: "127.0.0.1"

        search:
          formats:
            - html
            - csv
            - json
            - rss
          language: en

        engines:
          - name: google
          - name: stackoverflow
          - name: github
      '';
    };

    search.Deployment.searxng = {
      metadata.labels.app = "searxng";
      spec = {
        replicas = 2;
        selector.matchLabels.app = "searxng";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "searxng";
          spec = {
            automountServiceAccountToken = false;
            nodeSelector."kubernetes.io/hostname" = "nexus";
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1001;
              runAsGroup = 1001;
              fsGroup = 1001;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              searxng = {
                image = "searxng/searxng:latest";
                imagePullPolicy = "Always";
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                env = {
                  _namedlist = true;
                  SEARXNG_SECRET.value = "REDACTED_SEARXNG_SECRET_KEY";
                  SEARXNG_PORT.value = "8080";
                  SEARXNG_BASE_URL.value = "https://search.cluster.local/";
                };
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "512Mi";
                    cpu = "500m";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = "http";
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = "http";
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  tmp = {
                    mountPath = "/tmp";
                  };
                  cache = {
                    mountPath = "/var/www/searxng/cache";
                  };
                  settings = {
                    mountPath = "/etc/searxng";
                  };
                };
              };
            };
            initContainers = {
              _namedlist = true;
              patch-settings = {
                image = "searxng/searxng:latest";
                command = ["/bin/sh" "-c" ''
                  cd /etc/searxng
                  sed -i 's/^    - html$/    - html\n    - csv\n    - json\n    - rss/' settings.yml
                  cat > limiter.toml << 'EOF'
                  [botdetection.ip_limit]
                  link_token = false
                  EOF
                ''];
                volumeMounts = {
                  _namedlist = true;
                  settings.mountPath = "/etc/searxng";
                };
              };
            };
            volumes = {
              _namedlist = true;
              tmp.emptyDir = { };
              cache.emptyDir = { };
              settings.emptyDir = { };
            };
          };
        };
      };
    };

    search.Service.searxng = {
      metadata.labels.app = "searxng";
      spec = {
        type = "NodePort";
        selector.app = "searxng";
        ports = [
          {
            name = "http";
            port = 7777;
            targetPort = 8080;
            nodePort = 30888;
            protocol = "TCP";
          }
        ];
      };
    };

    search.Ingress.searxng = {
      metadata = { labels.app = "searxng"; annotations."caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true"; };
      spec = { ingressClassName = "caddy"; rules = [
        { host = "search.lan"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "searxng"; port.number = 7777; }; }]; }
        { host = "search.cluster.local"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "searxng"; port.number = 7777; }; }]; }
      ]; };
    };

    search.NetworkPolicy.allow-searxng-ingress = {
      metadata.labels = {
        app = "searxng";
        policy = "allow-ingress";
      };
      spec = {
        podSelector.matchLabels.app = "searxng";
        policyTypes = [ "Ingress" ];
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels.name = "ingress-nginx"; }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
          {
            from = [ { podSelector = { }; } ];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
        ];
      };
    };

    search.NetworkPolicy.allow-searxng-egress = {
      metadata.labels = {
        app = "searxng";
        policy = "allow-egress";
      };
      spec = {
        podSelector.matchLabels.app = "searxng";
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [
              { namespaceSelector.matchLabels.name = "kube-system"; }
            ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };
  };
}

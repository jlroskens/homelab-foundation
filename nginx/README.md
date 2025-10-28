# nginx

Nginx has been packaged with certbot and configured to renew certificates via DNS01 challenges to Cloudflare.

## Prerequisites

- A registered domain with Cloudflare enabled to manage it
- Cloudflare API key with DNS read/write access
- Docker installed and running wherever this is being installed
- Web Sites/Services on your or network for Nginx to proxy
- `A` record(s) registered on internal DNS for those same HTTP service(s).

## Setup

### Configure Environment

The docker build depends on pre-configured Nginx configs prior to building. There are example configs under the [environments](./environments) folder that can be used as a starting template. Copy each of these over to an environment specific name.

```
cp environments/example.env environments/mydomain.env
cp environments/example.nginx.conf environments/mydomain.nginx.conf
cp environments/example.certbot.ini environments/mydomain.certbot.ini
```

1. Configure a environments/{environment}.env file. The variables in this file inform the build and compose scripts of your `nginx.conf` and `certbot.ini` file names.
    ```
    NGINX_CONFIG_FILE_NAME='mydomain.nginx.conf'      # The nginx config file for this environment. Must be in the same directory as the .env file.
    CERTBOT_CONFIG_FILE_NAME='mydomain.certbot.ini'   # The cerbot config file for this environment. Must be in the same directory as the .env file.
    ```
2. Configure the `mydomain.certbot.ini` with your email and desired domains. Review the rest of the settings, but they should be fine as they are.
    ```
    domains = dns1.local.mydomain.example.com,proxmox-answer.local.mydomain.example.com
    email = myname@example.com
    ```
3. Configure the `mydomain.nginx.conf` nginx config, adding or removing server's as needed.  The default / example files assume a unique FQDN per service / site, but any Nginx configuration certbot can manage will work. This means don't attempt to set up listen directives for any ports, or configure tls certificates. Certbot will handle all that for you.
    ```
    server  {
        server_name dns1.local.mydomain.example.com;        # This is the hostname configured in your DNS and being requested by clients.
        location  / {
            # No listen directive. You can add it, but it will cause issues if certbot can't figure out how to update / remove it.
            proxy_pass  http://technitium-dns-server:5380;  # Url to the docker container name. This only works if the container is running on the same network(s) as nginx.
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
        }
    }
    server  {
            server_name proxmox-answer.mydomain.local.example.com;
            location  / {
                    proxy_pass  http://proxmox-answer-server:8000/answer;  # In this example requests to location '/' are being proxied to the '/answer' path of the target service
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection 'upgrade';
                    proxy_set_header Host $host;
                    proxy_cache_bypass $http_upgrade;
            }
    }
    ```
4. If you skipped over registering DNS `A` records for the `server_name` entries above, do it now.

### Build Custom Nginx

The [build.sh](build.sh) script builds a custom docker image from the [nginx](https://hub.docker.com/_/nginx) docker image that includes a certbot installation and scheduled cronjob to automatically renew certificates and configure nginx for TLS.

Provided your configuration is set up correctly, running the `build.sh` script is fairly straightforward. It only requires one argument, the path to your `{environment}.env` file. When ran, it copies all files under the `artifacts` directory and merges in the `certbot.ini` files `nginx.conf` you configured earlier. For this reason, any changes any of these files requires the image be rebuilt as those files are "baked" into the docker image. In other words - changed a file? rerun `build.sh`.


```
./build.sh environments/mydomain.env
```

The script should alert you of any missing arguments for variables in your `environments/{environment}.env` file. Once the build completes, then we can move on to composing the docker service.

### Composing Nginx

The [compose.sh](build.sh) script executes `docker compose up` using the [compose.yaml](compose.yaml) file to create or restart a new nginx-proxy container. This script requires a `CLOUDFLARE_DNS_API_TOKEN` be configured as an inline or an export prior to running the script. For details on configuring an API token, see https://certbot-dns-cloudflare.readthedocs.io/en/stable/.

Compose your service
```
CLOUDFLARE_DNS_API_TOKEN='xxxxx' ./compose.sh
```

This script only needs to be ran whenever you've made changes to a configuration file or API token. The container will start on it's own through restarts / shutdowns. The compose.yaml has been configured to automatically restart the container unless you manually stop it.

### Verification / Troubleshooting

The easiest way to verify is to go to one of the `server_name` sites configured in your `mydomain.nginx.conf` file in a browser. If everything worked, the site should load using https with a valid certificate from letsencrypt. If not you'll want to verify the container actually started and stayed running. It may be `bootlooped`.

Verify container exists:
```docker container ls```
A container `nginx-proxy` should be in the list.

Check the logs:
```docker container logs nginx-proxy```
This should give you some indication of why your container isn't functioning properly.
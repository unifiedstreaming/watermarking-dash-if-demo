FROM quay.io/varnish-software/varnish-plus:latest

ARG DOMAIN=my-domain-test
RUN echo "DOMAIN: ${DOMAIN}"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY default.vcl.in /etc/varnish/default.vcl.in

USER root

# # Install make for development purposes
RUN apt -y update \
    && apt -y install systemd vim make certbot

# Remove the default.vcl inside quay.io/varnish-software/varnish-plus image
RUN rm --p /etc/varnish/default.vcl
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN chown -R varnish /var/log/varnish/

# Add cert stuff
COPY letsencrypt.vcl /etc/varnish/letsencrypt.vcl

COPY certbot-deploy-hook.sh /usr/bin/certbot-deploy-hook
RUN chmod +x /usr/bin/certbot-deploy-hook

EXPOSE 80
EXPOSE 443

# USER varnish

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

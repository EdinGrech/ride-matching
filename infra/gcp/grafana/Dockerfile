FROM grafana/grafana:12.1.0

ARG GCP_PROJECT
USER root
COPY provisioning /etc/grafana/provisioning
COPY dashboards /var/lib/grafana/dashboards
RUN sed -i "s/__GCP_PROJECT__/${GCP_PROJECT}/g" /var/lib/grafana/dashboards/ride-gcp-load-test.json
USER grafana

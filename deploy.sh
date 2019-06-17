#!/usr/bin/env bash

GRAFANA_PASSWORD=${1}

prom_url=`oc get secrets -n openshift-monitoring grafana-datasources -o go-template='{{index .data "prometheus.yaml"}}' | base64 --decode | jq '.datasources[0].url'`
prom_user="internal"
prom_pass=`oc get secrets -n openshift-monitoring grafana-datasources -o go-template='{{index .data "prometheus.yaml"}}' | base64 --decode | jq '.datasources[0].basicAuthPassword'`

oc new-project grafshift
oc process -f templates/grafana.yml -p "GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASSWORD}" -p "PROMETHEUS_URL=${prom_url}" -p "PROMETHEUS_USER=${prom_user}" -p "PROMETHEUS_PASSWORD=${prom_pass}" | oc create -f -

for i in `seq 1 20`
do
  echo "Seeing if pod is up... ${i}"
  running=`oc get po -n grafshift | grep running -i -c`
  if [ ${running} -gt 0 ]
  then
    echo "Grafana Pod is up..."
    break
  fi
  sleep 1
done

# Give route a chance to be ready
sleep 5

grafshift_route=`oc get routes -n grafshift -o=json | jq -r '.items[0].spec.host'`

api_key=`curl -s -H "Content-Type: application/json" -H "Accept: application/json" -X POST -d '{"name":"grafyaml","role":"Admin"}'  http://admin:${GRAFANA_PASSWORD}@${grafshift_route}/api/auth/keys | jq -r '.key'`

# Clear GrafYaml Cache
rm -rf ~/.cache/grafyaml/cache.dbm

# Creates local GrafYaml config file
echo "[cache]" > .grafyaml_config
echo "enabled = false" >> .grafyaml_config
echo "[grafana]" >> .grafyaml_config
echo "url = http://${grafshift_route}" >> .grafyaml_config
echo "apikey = ${api_key}" >> .grafyaml_config

echo "Uploading Dashboards to http://${grafshift_route}/"
grafana-dashboard --config-file .grafyaml_config update dashboards/

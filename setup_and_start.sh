# Before executing this file, create secret.yml file
# vi secret.yml
# and copy paste from quay.io --> username on top --> Account setttings --> Robot accounts 
# --> click on Robot --> Kubernetes secret --> View username-build-secret.yml

# if command to check if secret.yml has been created. 
# Also check for full-pipeline.yml and pipeline-run.yml
# If not, exit with error message.

oc new-project inference
oc apply secret.yml
# grep the secret name

oc create sa mlperf
oc edit sa mlperf
#somehow incorporate secret name into sa

oc adm policy add-scc-to-user privileged -z mlperf
oc adm policy add-scc-to-user anyuid -z mlperf
oc apply -f full-pipeline.yml
oc apply -f pipeline-run.yml

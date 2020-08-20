# Tekton Pipeline for MLPerf Inference Benchmarking on Openshift using GPUs

The source of MLPerf Inference Benchmark Implementation is located at https://github.com/mlperf/inference.git .

The version of inference benchmark is v0.5 and the list of benchmark tuypes tested are described under "classification_and_detection".
The Dockerfile.gpu and run_local.sh have been modified and download_data.sh has been created for this pipeline. All the final modified files are located at https://github.com/AICoE/inference.git . This is where the PipelineResources point at too.

Here, a tekton pipeline that will build the image from Dockerfile, push the image to quay registry, pull that image, download data and run the benchmark on GPU. Part of the pipeline yamls were adopted from [AICoE](https://github.com/AICoE/mlperf-tekton/tree/master/object_detection).

Pipeline consists of three tasks: `buildah`, `dataset` and `run`. `buildah` consists of two steps: `build` and `push`, while `dataset` and `run` consist of only one step: `download` and `run`, respectively.

When the pipeline is run, it first creates one pod for `buildah` task, which will have two containers initiated: one for `build` step and another for `push` step. After `buildah` task is complete, another pod will be created for `dataset` task with `download` container. Once `dataset` task is complete, the pod for `run` task with `run` container will be initiated. Please note that there would be other containers created within a pod for each task. They are intended for pulling images and other background processes.

## Requirements 
**Openshift Container Platform (tested on 3.11 only, but should work on 4.x as well)**

Free 1-hour access is also available through [learn.openshift.com](learn.openshift.com)

**Tekton**

**Openshift Pipelines**

**Quay repository account and robot access**

Create an account in [quay.io](quay.io). Once account is setup, on the top right click "Create New Repository" and create a "Container Image Repository" with a name of "inference", set it to public, choose empty repository and click "Create Public Repository".

Now let's set up the robot that will allow access to repositories. On top right, click on username, then "Account Settings". On the left, click on the image of a robot, then on the right "Create Robot Account". Then, fill in "build" for a name and provide description if desired and click "Create Robot Account". Choose all repositories that need to be accessed. In this case, it is only "inference", whose permissions need to be set "Write" and click "Add permissions". This robot now will facilitate push, pull access to your repository.

## Setup

Login to openshift:

```bash
oc login -u admin
```
It will ask for your password. 

Fork this repository on own Github account and then clone it into local machine where pipelines would be running:

```git
git clone https://github.com/AICoE/mlperf-inference-tekton-pipeline.git
```

Now let's set up the Quay registry access for the service account. In quay registry, click on your username --> Account Settings --> robot icon on the left. Click on the robot account name that was set up earlier and go to "Kubernetes Secret". Click on "View *username*-build-secret.yml". Copy the text into your local machine where benchmark will be run via `vi secret.yml`. 

And then execute the `setup_and_start.sh` script. The script won't run if previous steps were incomplete. The script will create a new project called *inference*, setup the image push privileges (ie. apply the secret file, create serviceaccount called *mlperf*, incorporate the secret into serviceaccount and grant necessary scc privileges), upload the PV

Create a service account called "matmul":
```bash
oc create sa matmul
```
Add the needed privileges to the service account to build, push and pull images:
```bash
oc adm policy add-scc-to-user privileged -z matmul
oc adm policy add-scc-to-user anyuid -z matmul
```
`-z` refers to service account specifically. 



Before applying the secret, inside the yaml file change the `name:` of the secret to "matmul-secret". Now let's apply the secret (if downloaded file, use the filename):
```bash
oc apply -f secret-file.yml
```
`-f` refers to filename.

The creation of secret can be confirmed by running the command below and checking for the name:
```bash
oc get secret
```
Now we need to let the service account know the secret:
```bash
oc edit sa matmul
```
and add two identical lines that are shown below:
```bash
imagePullSecrets:
- name: matmul-secret
- name: ...
...

secrets:
- name: matmul-secret
- name: ...
```
and exit (ie. `ESC` and `:wq`)

Now it is good to go!


## Run the pipeline

Go to the folder that was cloned where "full-pipeline.yml" file is. First, let's upload all pipeline resources, tasks, pipeline and request for persistent volume claim:
```bash
oc apply -f full-pipeline.yml
```
which should give output of:
```bash
pipelineresource.tekton.dev/mm-repo created
pipelineresource.tekton.dev/mm-build-image created
persistentvolumeclaim/mm-runtime-pvc created
task.tekton.dev/mm-buildah created
task.tekton.dev/mm-run created
pipeline.tekton.dev/matmul-pl created
```


And now let's start the pipeline:
```bash
oc apply -f pipeline-run.yml
```

Now the pipeline is running. It can be confirmed with:
```bash
oc get pr
```


## Checking the pipeline-run progress

As mentioned earlier, pipeline consists of two tasks. First task has two steps: `build` and `push`. Second task has only `run` step.

To see progress, we can check the logs of those specific steps (each task is a separate pod and each step is a separate container).

First, check the pod name:
```bash
oc get pods
```

which will give something similar to:
```
NAME                                READY   STATUS    RESTARTS   AGE
matmul-pr-build-g7gwd-pod-47196b    3/5     Running   0          2m2s
```
Status will change from `Init:0/4` to `PodInitializing` to `Running`. Once running, each step needs to be monitored separately. Copy the name of the pod:
```bash
oc logs -f matmul-pr-build-g7gwd-pod-47196b -c step-build
```
And logs should appear. Remember to change the pod name to the one generated on the local machine. It could also be written to a file by adding ` > build-progress.log`.

Please note that the matmul.py code requires (and Dockerfile instructs installation of) Tensorflow 2.x which runs on CUDA 10.1. To have a working Tensorflow 2.x on CUDA 10.2, it needs to be installed manually (see https://github.com/tensorflow/tensorflow/issues/38194 ).

Step `push` and `run` could be checked similarly. Remember that `run` step will have a different pod and a pod name.

Once pipeline run is complete, check the logs of `run` step and at the end, it should look similar to this:
```bash
Shape: (1500, 1500) Device: /gpu:0
Time taken: 0:00:02.346886
```
The pipeline-run has been completed! All tasks, pipelinerources, pipeline, pipeline-run and pvc can then be deleted if not needed anymore. ie:
```bash
oc delete tasks --all -n matmul
```

To perform further benchmarks, the shape of the matrix can be modified by changing the number in the following line in `full-pipeline.yaml` under `mm-run` Task:
```
command: ["python3", "matmul.py", "gpu", "1500"]
```


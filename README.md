# Tekton Pipeline for MLPerf Inference Benchmark on Openshift using CPUs

The source of MLPerf Inference Benchmark Implementation is located at https://github.com/mlperf/inference.git .

The version of inference benchmark is v0.5 and the list of benchmark types tested are described under "classification_and_detection".
The `Dockerfile.cpu` and `run_local.sh` have been modified and `download_data.sh` has been created for this pipeline. All the final modified files are located at https://github.com/AICoE/inference.git . This is where the PipelineResources point at too.

Here, a tekton pipeline that will build the image from Dockerfile, push the image to quay registry, pull that image, download model and data and run the benchmark on CPU. Part of the pipeline yamls were adopted from [AICoE](https://github.com/AICoE/mlperf-tekton/tree/master/object_detection).

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

## Setup and Running of the Pipeline

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

And then execute the `setup_and_start.sh` script. The script won't run if previous steps were incomplete. The script will create a new project called *inference*, setup the image push privileges (ie. apply the secret file, create serviceaccount called *mlperf*, incorporate the secret into serviceaccount and grant necessary scc privileges), request storage (ie. PersistentVolumeClaim), upload all pipelineresources, tasks and pipeline. It will then run the pipeline (ie. execute PipelineRun).

The following outputs are expected upon execution of commands inside `setup_and_run.sh`:

Execution of `oc new-project inference` creates a new project called inference and shows the following:
```bash
Now using project "inference" on server "https://XXX".

You can add applications to this project with the 'new-app' command. For example, try:

    oc new-app centos/ruby-25-centos7~https://github.com/sclorg/ruby-ex.git

to build a new example application in Ruby.
```

Execution of `oc apply secret.yml` creates the secret and outputs the following:
```bash
secret/username-secret created
```

Execution of `oc create sa mlperf` and `oc edit sa mlperf` creates a service account called *mlperf* and updates its secrets, outputting the following:
```bash
serviceaccount/mlperf created
serviceaccount/mlperf edited
```

Execution of both `oc adm policy ...` updates the security context constraints for building and pushing the images in containers and outputs:
```bash
scc "privileged" added to: ["system:serviceaccount:inference:mlperf"]
scc "anyuid" added to: ["system:serviceaccount:inference:mlperf"]
```

Execution of `oc apply -f full-pipeline.yml` uploads all pipeline resources, tasks, pipeline and request for persistent volume claim and shows the following:
```bash
pipelineresource.tekton.dev/inf-repo created
pipelineresource.tekton.dev/inf-build-image created
persistentvolumeclaim/inf-pvc created
task.tekton.dev/inf-build created
task.tekton.dev/inf-dataset created
task.tekton.dev/inf-run created
pipeline.tekton.dev/inference-pl createdoc 
```

Execution of `oc apply -f pipeline-run.yml` runs the pipeline and shows the following:
```bash
pipelinerun.tekton.dev/inference-pr created
```
The running of pipeline can be confirmed with:
```bash
oc get pr
```
which outputs:
```bash
NAME           SUCCEEDED   REASON    STARTTIME   COMPLETIONTIME
inference-pr   Unknown     Running   6m    
```

## Checking the pipeline-run progress

As mentioned earlier, pipeline consists of three tasks. First task has two steps: `build` and `push`. Second and third tasks have only step each (ie. `download` and `run`).

To see progress, we can check the logs of those specific steps (each task is a separate pod and each step is a separate container).

First, check the pod name:
```bash
oc get pods
```

which will give something similar to:
```
NAME                                  READY   STATUS    RESTARTS   AGE
inference-pr-build-s6t58-pod-2wt26    3/5     Running   0          2m2s
```
Status will change from `Init:0/4` to `PodInitializing` to `Running`. Once running, each step needs to be monitored separately. Copy the name of the pod:
```bash
oc logs -f inference-pr-build-s6t58-pod-2wt26 -c step-build
```
And logs should appear. Remember to change the pod name to the one generated on the local machine. It could also be written to a file by adding ` > build-progress.log`.

Step `push`, `download` and `run` could be checked similarly. Remember that `download` and `run` steps each will have a different pod and a pod name.

Once pipeline run is complete, `oc get pods` outputs:
```bash
TBD
```

The logs of `run` step and at the end should look similar to this:
```bash
STARTING RUN AT 2020-08-21 04:07:24 PM
python_main
INFO:main:Namespace(accuracy=False, backend='onnxruntime', cache=0, config='/root/v0.5/mlperf.conf', count=None, data_format='NHWC', dataset='coco-300', dataset_list=None, dataset_path='/root/v0.5/classification_and_detection/dataset/dataset-coco-2017-val', find_peak_performance=False, inputs=None, max_batchsize=32, max_latency=None, model='/root/v0.5/classification_and_detection/dataset/ssd_mobilenet_v1_coco_2018_01_28.onnx', model_name='ssd-mobilenet', output='/root/output/onnxruntime-cpu/ssd-mobilenet', outputs=['num_detections:0', 'detection_boxes:0', 'detection_scores:0', 'detection_classes:0'], profile='ssd-mobilenet-onnxruntime', qps=None, samples_per_query=None, scenario='SingleStream', threads=64, time=None)
INFO:coco:loaded 5000 images, cache=0, took=35.7sec
2020-08-21 16:08:00.490358041 [W:onnxruntime:, graph.cc:863 Graph] Initializer zero__164 appears in graph inputs and will not be treated as constant value/weight. This may prevent some of the graph optimizations, like const folding. Move it out of graph inputs if there is no need to override it, by either re-generating the model with latest exporter/converter or with the tool onnxruntime/tools/python/remove_initializer_from_input.py.
...
...
...
/root/v0.5/classification_and_detection/python/coco.py:115: VisibleDeprecationWarning: Creating an ndarray from ragged nested sequences (which is a list-or-tuple of lists-or-tuples-or ndarrays with different lengths or shapes) is deprecated. If you meant to do this, you must specify 'dtype=object' when creating the ndarray
  self.label_list = np.array(self.label_list)
INFO:main:starting TestScenario.SingleStream
TestScenario.SingleStream qps=2.81, mean=0.3561, time=364.836, queries=1024, tiles=50.0:0.3068,80.0:0.4127,90.0:0.4998,95.0:0.5796,99.0:0.6926,99.9:0.8962
ENDING RUN AT 2020-08-21 04:14:09 PM
```

To determine the duration of the inference benchmark, take the difference between **STARTING RUN AT** and **ENDING RUN AT**.

The pipeline-run has been completed! All tasks, pipelinerources, pipeline, pipeline-run and pvc can then be deleted if not needed anymore by executing `cleanup.sh`, which will output:
```bash
TBD
```

If the project is not needed anymore, it can be deleted with `oc delete project inference`. To delete all remaining logs from running containers, execute `docker system prune --all` and then `y`.

## Details of the Default Benchmark and How to Choose a Different one

The benchmark that is executed by default is the *ssd-mobilenet 300x300* with the command `./run_local.sh pytorch ssd-mobilenet gpu` in the `run` task.

Currently, use of a different benchmarking model requires manual change of the `download_dataset.sh` and `full-pipeline.yml` scripts. However, this will also be automated in a near future. 

For now, to change the benchmarking model, fork the main repository (https://github.com/AICoE/inference.git) to your own. In `full-pipeline.yml` that has been cloned to the local machine, change the value of `repo` PipelineResource to your own repository (line 10). Forking is necessary since the `download_dataset.sh` will need to be edited.

Now, choose a model with framework of interest (ie. tf or pytorch) [here](https://github.com/AICoE/inference/tree/master/v0.5/classification_and_detection). Right click on "from zenodo" link under *Model link* column and "Copy link address". 

Open `download_dataset.sh` file in the forked repository and edit the file. Change the link of the below line to the one that was copied earlier:
```bash
wget -q https://zenodo.org/record/3239977/files/ssd_mobilenet_v1.pytorch
```
Commit changes.

In the `full-pipeline.yml`, scroll down to `run` task and change the `command` line:
```bash
command: ["/bin/bash", "./run_local.sh", "pytorch", "ssd-mobilenet", "gpu"]
```
to the model and framework of interest. The format is:
```bash
"./run_local.sh", "backend", "model", "device"

backend is one of [tf|onnxruntime|pytorch|tflite]
model is one of [resnet50|mobilenet|ssd-mobilenet|ssd-resnet34]
device is one of [cpu|gpu]


For example:

"./run_local.sh", "tf", "resnet50", "gpu"
```

The `dataset` task downloads the necessary datasets for all benchmark models mentioned in `classification_and_detection`.

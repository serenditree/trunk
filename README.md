# Serenditree Trunk

## About

This project provides the command-line interface, GitOps truth, and IaC for Serenditree.

Images are built using buildah. The steps for building and running an image are defined in files called `plot.sh`.
Folders containing a file called `plot.sh` contain everything needed to build images and run containers.
```
> sc plots
ORDINAL  SERVICE            IMAGE                     TAG     PATH
1        soil-java-base     serenditree/java-base     latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/java/plot-java.sh:base:0
2        soil-java-builder  serenditree/java-builder  latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/java/plot-java.sh:builder:1
3        soil-node-base     serenditree/node-base     latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/node/plot-node.sh:base:0
4        soil-node-builder  serenditree/node-builder  latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/node/plot-node.sh:builder:1
5        soil-nginx         serenditree/nginx         latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/nginx/plot.sh
6        testing            serenditree/testing       latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/test/plot.sh
7        soil-buildah       serenditree/buildah       latest  /home/tanwald/Development/Serenditree/trunk/plots/soil/buildah/plot.sh
8        root-user          serenditree/root-user     latest  /home/tanwald/Development/Serenditree/trunk/plots/root/user/plot.sh
9        root-seed          serenditree/root-seed     latest  /home/tanwald/Development/Serenditree/trunk/plots/root/seed/plot.sh
10       root-map           serenditree/root-map      latest  /home/tanwald/Development/Serenditree/trunk/plots/root/map/plot.sh
11       root-wind          serenditree/root-wind     latest  /home/tanwald/Development/Serenditree/trunk/plots/root/wind/plot.sh
12       branch-user        serenditree/branch-user   latest  /home/tanwald/Development/Serenditree/trunk/plots/branch/plot-branch.sh:user:user:0
13       branch-seed        serenditree/branch-seed   latest  /home/tanwald/Development/Serenditree/trunk/plots/branch/plot-branch.sh:seed:seed:1
14       branch-poll        serenditree/branch-poll   latest  /home/tanwald/Development/Serenditree/trunk/plots/branch/plot-branch.sh:poll:user:2
15       leaf               serenditree/leaf          latest  /home/tanwald/Development/Serenditree/trunk/plots/leaf/plot.sh
```

## Structure
```
├── charts            # Helm
│   ├── branch          # Quarkus
│   ├── leaf            # Angular
│   ├── root          # Backend
│   │   ├── map         # Tileserver
│   │   ├── seed        # Opensearch
│   │   ├── user        # Postgres
│   │   └── wind        # Kafka
│   ├── soil          # Common chart templates
│   ├── terra         # Infra
│   │   ├── argocd      # Argocd
│   │   ├── cache       # Valkey/DragonflyDB
│   │   ├── certs       # Cert-manager
│   │   ├── cilium      # Cilium + Hubble
│   │   ├── collect     # Opentelemetry Collector
│   │   ├── gateway     # Traefik Gateway/Envoy Gateway
│   │   ├── sql         # CloudnativePG Operator
│   │   ├── scale       # Karpenter/Cluster Autoscaler
│   │   ├── scope       # Kube-Prometheus-Stack
│   │   ├── streams     # Strimzi Operator
│   │   ├── tekton      # Tekton Pipelines
│   │   ├── testing     # K6 load testing
│   │   └── vault       # Openbao + External Secrets Operator
│   └── tree            # App of Apps
├── cli-template.sh   # Argbash template for CLI
├── cli.sh            # CLI
├── plots             # Scripts for building images and running containers
│   ├── branch          # Quarkus services
│   ├── leaf            # Angular service
│   ├── root          # Backend services
│   │   ├── map         # Tileserver
│   │   ├── seed        # Opensearch
│   │   ├── user        # Posgres
│   │   └── wind        # Kafka
│   └── soil            # Base- and builder-images
├── rc                # Resources
│   ├── compose         # Podman compose file
│   ├── config          # Config files
│   ├── jobs            # Kubernets jobs and test-runs.
│   ├── operators       # OLM subscriptions
│   └── templates       # Template files
└── src               # Source
    ├── kubernetes      # IaC Kubernetes
    ├── openshift       # IaC Openshift (currently not maintained)
    ├── storage         # IaC object storage (independent of cluster)
    ├── cluster.sh      # Cluster commands
    ├── compose.sh      # Podman compose commands
    ├── container.sh    # Image/Container manipulation
    ├── context.sh      # Context settings
    ├── env.sh          # Config
    ├── git.sh          # Git commands for each submodule
    ├── helm.sh         # Helm pull, package/push, and template 
    ├── login.sh        # Login to registries and repos
    ├── plots.sh        # Run plots
    ├── pods.sh         # Control the local pod
    ├── status.sh       # Local and cluster status and checks
    ├── terra.sh        # IaC commands
    ├── test.sh         # K6 load testing
    ├── update.sh       # Update charts, images, mvn, yarn,...
    └── utils.sh        # Cross-cutting concerns
```

The file `cli-template.sh` is processed by argbash which creates `cli.sh`, the entrypoint for the command-line interface
that processes command-line arguments and calls the functions of dedicated script-files.

```
Serenditree CLI
Usage:  sc [-a|--all] [-c|--compose] [--delete] [-d|--dryrun] [-E|--expose] [-h|--help] [--init] [--insert] 
[--integration] [-k|--kubernetes] [-l|--local] [-n|--notify] [--open] [-o|--openshift] [-P|--prod] [--reset] [--restore] 
[--setup] [-T|--test] [--upgrade] [-w|--wait] [-D|--debug] [-v|--verbose] [-y|--yes] [-x|--xissuer] [-s|--scale <arg>] 
[-g|--gateway <arg>] [--resume <arg>] [--] <command> ... 

	<command>:          Command to execute. Please type sc <help> for a list of commands!
	... :               Other arguments passed to command.
	-a, --all:          All...
	-c, --compose:      Run or build for podman compose.
	--delete:           Deletion flag.
	-d, --dryrun:       Activates dryrun mode.
	-E, --expose:       Exposes database ports on local pods.
	-h, --help:         Command help. Please type sc <help> for a list of commands!
	--init:             Initialization flag.
	--insert:           Inserts a new plot.
	--integration:      Run for integration testing.
	-k, --kubernetes:   Use vanilla kubernetes.
	-l, --local:        Target local cluster.
	-n, --notify:       Enable desktop notifications.
	--open:             Open plots.
	-o, --openshift:    Use openshift.
	-P, --prod:         Sets the target stage to prod. (default is dev)
	--reset:            Reset flag.
	--restore:          Restore flag.
	--setup:            Setup flag.
	-T, --test:         Sets the target stage to test. (default is dev)
	--upgrade:          Upgrade flag.
	-w, --wait:         Wait for completion.
	-D, --debug:        Debug flag.
	-v, --verbose:      Verbose flag.
	-y, --yes:          Assumes yes on prompts.
	-x, --xissuer:      Set cert-issuer to prod when stage is not prod and vice versa.
	-s, --scale:        Auto-scaling implementation. (default: 'karpenter')
	-g, --gateway:      Gateway implementation. (default: 'traefik')
	--resume:           Resume plots from the given plot. (no default)

	Local commands:
	up [svc]:           Starts a local development stack or a single container. [--expose] [--wait] [--compose] [--integration]
	down [svc]:         Stops local stack or single containers. [--compose] [--integration]

	build [svc]:        Builds all or individual images.
	backup:             Backup local databases.
	charts:             Prints charts information.
	completion:         Adds bash-completion script to /etc/bash_completion.d/. [--all]
	compose [--] <cmd>: Run podman compose commands.
	config:             Prints cli and java config.
	context [id]:       Switch or display contexts.
	database <db>:      Open local database console. {user|seed}
	deploy [svc]:       Deploys all or individual services to the local stack.
	env:                Prints global environment variables based on context.
	expose:             Port-forward operation-services. [--reset|--delete]
	git [--] <cmd>:     Execute arbitrary git commands.
	helm <cmd> [chart]: Push commons, update dependencies or render charts.
	health:             Runs health-checks on services. [--wait|--verbose]
	loc:                Prints lines of code.
	login <reg>:        Login to configured registries.
	logs|log [svc]:     Prints logs of all or individual services on the local pod.
	plots:              Prints or inserts/deletes plots. [--open] [--insert|--delete]
	proxy:              Proxy kubernetes services.
	ps:                 Lists locally running serenditree containers.
	push [svc]:         Push all or individual images.
	registry:           Inspect images in remote registries. [--verbose]
	release:            Updates the parent git repository and pushes new commits.
	restore:            Restores local databases from remote data.
	rotate:             Rotates JWK material locally.
	status:             Prints status information and checks prerequisites.
	storage <cmd>:      Provision or destroy storage independent of clusters. {up|down}
	terra <cmd>:        Run infra commands with all variables set.
	test:               Prepares and runs tests. [--delete][--verbose]
	update [comp]:      Update components.

	Cluster commands:
	up:                 Cluster start/setup. [--init] [--setup] [--wait] [--scale]
	down:               Cluster stop/deletion. [--reset|--delete] [--yes]

	backup:             Setup backup cronjobs or run backups from cronjobs. [--setup]
	certificate:        Prints certificate information.
	clean:              Deletes dispensable resources.
	database <db>:      Open database console. {user|seed}
	deploy:             Deploys new images.
	expose:             Port-forward operation-services. [--reset|--delete]
	keys:               List all keys in the cluster's vault.
	login:              Login to OpenShift and its internal registry.
	logs <svc>:         Prints logs of the given pod(s).
	proxy:              Proxy kubernetes services.
	registry [img]:     Inspects the OpenShift image registry.
	resources [csv]:    Prints resource allocations. Optionally in CSV.
	restore:            Restore databases.
	status:             Prints cluster status information.
	tekton [svc]:       Triggers tekton runs for all or individual services.
	test:               Run tests using k6-operator. [--delete]
	unseal:             Unseal the cluster's vault

Please type 'sc <command> --help' for details about a certain command!
```

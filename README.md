# CodeReady Containers, Istio, and Egress

This small set of examples is designed to teach you about Istio egress control via Sidecar policies using Red Hat's CodeReady Containers and the OpenShift Service Mesh Operator.

## Overview

Each step is prepended with a number. The first step, for example, is number `00`. Kubernetes manifests associated with the step have the file extension `.yml`. Scripts associated with the step have the file extension `.sh`. You should run the scripts to apply the manifests, but you can look at them in a text editor or by running `cat` or `less` on them if you like.

The manifests can be read and possibly reused, though in some cases the scripts are designed to provide a specific environment for them. Consider them symbiotic. In general, the scripts will echo to the terminal what it is that they're doing so that you can follow along. There are some cases where the scripts are quieter for the sake of readability, but they should never apply manifests without showing you.

### NOTE

I tested these scripts on my own workstation for the purposes of making a demo. I run Fedora 33 on my system, and already use `libvirt` extensively - this is the default backend for CodeReady Containers. You may have a small amount of additional setup to go, depending on your configuration. In particular, note the problems that Fedora 33 sometimes has with [CRC's use of DNS](https://access.redhat.com/documentation/en-us/red_hat_codeready_containers/1.19/html/release_notes_and_known_issues/issues_on_linux). This workaround may no longer be requied by the time you run this with the latest version of CRC, but it has been applied to my system nevertheless.

As I've got 32 vCPU and 64 GB of RAM, these demo scripts may not work on your system out of the box. There may be resource constraints or simply timing problems that prevent you from succeeding. You should disable components of the control plane (especially Prometheus and Grafana) defined in `01-control-plane.yml` if you're resource constrained. If you have a hard time getting through these exercises on a lower-power machine due to timeouts, extend the timeouts of the steps that cause you trouble - or double them all by default by changing `common.sh`'s `wait_on` function.

## Walkthrough

### 00-setup

```bash
./00-setup.sh
```

This step will install the `crc-manager` [helper package](https://git.jharmison.com/jharmison/crc-manager) for your user, prompt you for how much CPU and Memory you'd like to provide for the CRC cluster (with some sensible defaults), then require you to enter your [pull-secret](https://cloud.redhat.com/openshift/create/local), and instantiate a CRC cluster for you. If you'd like to get fancy, `crc-up` (which is used to instantiate the cluster) can apply custom TLS certificates and custom `htpasswd` users. You can dig into the code for it if you like to see how it does those things, but they rely on some files existing in your `~/.crc` directory, along with your `pull-secret.json` (which the script will prompt you for).

Afterwards, it will log into the cluster using the default CRC mechanisms, validate that you are the cluster administrator, create the namespaces/projects that we need, and subscribe to the operators.

Finally, it just waits to validate that everything got stood up correctly. The operators in particular may take a little while.

After it finishes might be a good time to explore the crc cluster. You can open a web console to the cluster with `crc console` and display the credentials for logging in (if you didn't have an `htpasswd` setup) with `crc console --credentials`.

### 00.5-setup-reboot

```bash
./00.5-setup-reboot.sh
```

This step may be required if you deployed an htpasswd file. It's hard to time, so I just left it as an extra step. The OAuth operator may cause your CRC cluster node to reboot, rendering it unavailable. If this is the case, just run this step to wait for the cluster to come back up. It doesn't apply any manifests.

### 01-controlplane

```bash
./01-controlplane.sh
```

This step instantiates a basic OpenShift Service Mesh control plane, then waits for it to come up. This step must discreetly occur after operator installation, but doesn't actually deploy any workload to your cluster. You can monitor the control plane installation in your cluster if you like, to see what components come up and how they look.

### 02-bookinfo

```bash
./02-bookinfo.sh
```

This step deploys two full copies of the bookinfo example project from Istio. This small microservice application is designed to demonstrate the capabilities of OpenShift Service Mesh. There are a number of examples in the Istio project that demonstrate how one capability or another is used via the bookinfo application.

One of the deployed copies is under the `bookinfo-prod` namespace, and the other is under the `bookinfo` namespace. This is simply to demonstrate what a shared cluster might look like, with multiple applications and multiple environments (dev/test/prod) might look like. I expect you to be able to infer that this simple 2-copy app deployment could extend to many copies of many applications in your own environment.

After the application has finished deploying, a [remote shell](https://docs.openshift.com/container-platform/4.7/support/troubleshooting/investigating-pod-issues.html) is opened to the productpage container in the pod for that microservice (as opposed to the sidecar container on that pod) and that shell is used to validate connectivity to a variety of sites - namely, my own Gitea instance, Github.com, and an alternative ServiceMesh member for which there is no explicit policy allowing access. The externally accesible URL of the alternate deployment would have been accessible, except that there is no good DNS resolution for externally exposed services internal to the cluster in CodeReady Containers, due to the nature of faking DNS in this way. This wouldn't be the case in a production cluster. You should note that all three connections that we test return a status code 200.

If you'd like to visit the [bookinfo](http://bookinfo.apps-crc.testing) or [bookinfo-prod](http://bookinfo-prod.apps-crc.testing) applications, you can. They're relatively simple applications that display a simple productpage with reviews, ratings, and details. The data for each of them is hard-coded, so they're functionally identical.

### 03-sidecar

```bash
./03-sidecar.sh
```

This step applies a simple sidecar configuration that only applies egress policies for the specific mesh members in the `bookinfo` project that prevents them from reaching other mesh members in the cluster. After this simple configuration, another check is conducted to validate connectivity to the same URLs as before.

The only URL that should no longer return a status code 200 is the bookinfo-prod service, which is an internal URL resolvable only inside the cluster. This demonstrates how to isolate namespaces from each other simply using OpenShift Service Mesh. Note that without an egress policy defined for `bookinfo-prod`, or a more restrictive ingress policy defined for `bookinfo`, the reverse would not be true. That is, a connection from `bookinfo-prod` to `bookinfo` would succeed right now.

You can manually run that check, without a script, by doing something like this:

```bash
eval $(crc oc-env)
bookinfo_prod_productpage=$(oc -n bookinfo-prod get pod -l app=productpage -o jsonpath='.items[0].metadata.name')
url=http://productpage.bookinfo.svc.cluster.local:9080/productpage
oc -n bookinfo-prod -c productpage $bookinfo_prod_productpage << EOF
python -c '
import requests
try:
    print("$url: " + str(requests.get("$url")))
except Exception:
    print("$url: failed")'
EOF
```

The default Sidecar policy can be applied at the cluster level and inherited by all Service Mesh members, or it may be applied to projects explicitly (ideally via GitOps), or it may be applied via selector with labels for individual components. RBAC on the `Sidecar` resource inside OpenShift should be used to ensure that although clients may _see_ their Sidecar policy, they may not change it. GitOps workflows would enable them to pull-request a change to their policy into the main repository from which cluster configuration is derived, and pre-designated operations/security/networking personnel could be required reviewers of that change before allowing it to merge, and therefore take effect.

### 04-lockdown

```bash
./04-lockdown.sh
```

This step locks down the application by first defining explicitly a hostname that lives outside the mesh that it should be able to reach, then configuring the outboundTrafficPolicy on the `Sidecar` resource to only those services explicitly defined (instead of the default, which allows all non-mesh services). After the changes have been successfully rolled out, it conducts the same checks performed before, validating connectivity to a number of URLs. The only URL that should be accesible at this point (and therefore return an HTTP 200) is the explicitly defined `git.jharmison.com` host. You may define policy as tightly or widely scoped as desired, including the use of wildcards in some configurations.

Note that both services are still available and performing as expected. Feel free to open your local browser to [bookinfo](http://bookinfo.apps-crc.testing) or [bookinfo-prod](http://bookinfo-prod.apps-crc.testing) and note that they're both up and running as expected.

## Cleanup

If you want to bring the CodeReady Containers instance offline, run the following:

```bash
crc delete -f
```

If you want to remove CodeReady Containers from your system entirely, run the following:

```bash
crc cleanup
rm -rf ~/.crc
rm -f ~/.local/bin/crc
```

If you want to remove the `crc-manager` helper package, run the following:

```bash
pip uninstall --user crc-manager
```

## Summary

OpenShift Service Mesh, based on the Istio project, allows for incredibly granular control of the interactions between services. Beyond the traditional security benifits, and beyond the observibility benefits, it offers a simple way to control the way in which microservice components or multitenant environments interact. By providing a way to extend the mesh beyond your cluster using host-based (or IP-based) control over how services may communicate, you can lock down the processes to an extent never before seen - with relative ease.

If you'd like a more in-depth walkthrough of the capabilities of OpenShift Service Mesh, except for the specifics of Egress (which should be pretty well covered by the above), please consider asking your Red Hat representative about the [OpenShift Service Mesh Workshop](https://redhatgov.io/workshops/openshift_service_mesh/).

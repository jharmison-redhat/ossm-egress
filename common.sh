eval $(crc oc-env)

bookinfo_deployments=(
    details-v1
    ratings-v1
    reviews-v1
    reviews-v2
    reviews-v3
    productpage-v1
)

function wait_on {
    (
        { set +x ; } &>/dev/null
        interval=$1
        shift
        timeout=$1
        shift
        description="$1"
        shift
        echo "Waiting on $description"
        while ! eval "$@"; do
            printf '.'
            sleep $interval
            (( timeout -= interval ))
            [ $timeout -gt 0 ] || { printf '\n' ; return 1 ; }
        done
        printf '\n'
    )
}

function check_connections {
    (
        { set +x ; } &>/dev/null
        productpage_pod=$(oc get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}')

        for url in https://git.jharmison.com https://github.com http://productpage.bookinfo-prod.svc.cluster.local:9080/productpage; do
            oc rsh -c productpage $productpage_pod << EOF
python -c '
import requests
try:
    print("$url: " + str(requests.get("$url")))
except Exception:
    print("$url: failed")'
EOF
        done
    )
}

function finish_deployments {
    for deployment in ${bookinfo_deployments[@]}; do
        wait_on 5 300 "$deployment to be ${1}deployed" "oc get deployment $deployment | grep -qF '1/1'"
        label=$(oc get deployment $deployment -o jsonpath='{.spec.selector.matchLabels.app}')
        wait_on 5 300 "$deployment to finish rollout" "oc get pod -l app=$label | grep -qF '2/2'"
    done
}

function update_deployments {
    for deployment in ${bookinfo_deployments[@]}; do
        oc patch deployment/$deployment -p '{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt": "'$(date -Iseconds)'"}}}}}'
    done

    sleep 5

    finish_deployments '(re)'
}

set -ex

#!/bin/bash

set -uxf -o pipefail

usage() {
  echo $"Usage: $0 <timescaledb_version> <promscale_version>"
  exit 1
}

check_arg() {
  if [ ! $# -eq 2 ]; then
    echo "ERROR: need exactly two arguments, <cassandra_version> <schema_version>"
    usage
  fi
}

setup_promscale() {
  local tag=$1
  local image=timescale/promscale
  local params=(
    --rm
    --detach
    --name promscale
    --publish 9201:9201
    --publish 9202:9202
    --env PROMSCALE_DB_URI="postgres://postgres:password@timescaledb:5432/postgres?sslmode=allow"
    --network promscale
  )
  local cid=$(docker run ${params[@]} ${image}:${tag})
  echo ${cid}
}

setup_timescaledb() {
  local tag=$1
  local image=timescale/timescaledb-ha
  local params=(
    --rm
    --detach
    --publish 5432:5432
    --name timescaledb
    --env POSTGRES_USER=postgres
    --env POSTGRES_PASSWORD=password
    --network promscale
  )
  local cid=$(docker run ${params[@]} ${image}:${tag})
  # wait until timescaledb is ready.
  until docker exec -it ${cid} psql -U postgres -c 'SHOW timescaledb.license;'; do
      printf '.'
      sleep 5
  done
  echo ${cid}
}

teardown() {
  local timescaledb_cid=$1
  local promscale_cid=$2
  docker kill timescaledb promscale
  docker network rm promscale
  exit ${exit_status}
}

run_integration_test() {
  docker network create promscale

  local timescaledb_version=$1
  local promscale_version=$2
  local timescaledb_cid=$(setup_timescaledb ${timescaledb_version})
  trap "teardown ${timescaledb_cid}" EXIT
  local promscale_cid=$(setup_promscale ${promscale_version})
  STORAGE=grpc-plugin make grpc-storage-integration-test
  exit_status=$?
  trap "teardown ${timescaledb_cid} ${promscale_cid}" EXIT
}

main() {
  check_arg "$@"

  echo "Executing integration test for $1 with schema $2.cql.tmpl"
  run_integration_test "$1" "$2"
}

main "$@"

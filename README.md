# Tremor with Vector as a data source

This is a simple example integration between tremor and vector
with vector as a data source.

## Scenario

We use file based vector sources in this example. Vector has very flexible
support for file based log sources allowing vector to be used for log data
transformation and distribution.

Tremor is more focused on near real-time stream based sources and sinks.

By setting up a combined tremor and vector sidecar integrated over TCP sockets
we can leverage vector data sources and tremor's scripting and query languages.

## Setup

We need to download and install tremor and vector and make sure we have
their servers / daemons on the system path:

```bash
$ cd /Code
$ git clone git@github.com:tremorio/vector
$ cd vector && cargo build
$ cd /Code
$ git clone git@github.com:wayfair-tremor/tremor-runtime
$ cd tremor-runtime && cargo build
$ export PATH=/Code/vector/target/debug/vector:/Code/tremor-runtime/target/debug/tremor-server:$PATH
```

## Configure Vector as a Source

```toml
# Use a file based data source
[sources.in]
  type = "file"
  include = [ "input.log" ] 

# Push source data through a tcp socket from vector to tremor
[sinks.tcp]
  type = "socket"
  inputs = ["in"]
  address = "127.0.0.1:8888"
  mode = "tcp"
  encoding = "json"
```

## Configure Tremor as a Sink

```yaml
onramp:
  - id: vector
    type: tcp
    preprocessors:
      - lines
    codec: json
    config:
      host: 127.0.0.1
      port: 8888


offramp:
  - id: ok
    type: stdout
    codec: json
    config:
      prefix: "Valid> "
  - id: not_ok
    type: stdout
    codec: json
    config:
      prefix: "Invalid> "

binding:
  - id: main
    links:
      '/onramp/vector/{instance}/out': [ '/pipeline/main/{instance}/in' ]
      '/pipeline/main/{instance}/out': [ '/offramp/ok/{instance}/in' ]
      '/pipeline/main/{instance}/err': [ '/offramp/not_ok/{instance}/in' ]

mapping:
  /binding/main/01:
    instance: "01"
```

## Configure business logic

We setup a simple tremor script to validate the log data format and calculate
elapsed time from when its injected into vector by a bash script and received by
tremor's TCP socket onramp

```trickle
select
  match event of
    case r=%{ message ~= json||} => 
      match r.message of
        case %{ present application, present date, present message } =>
          { "ok": merge event of 
                   { "elapsed_ms": 
                     math::trunc((system::ingest_ns() - r.message.date) / 1000000) }
                  end
          }
        default => { "error": "invalid", "got": event }
      end
    default => { "error": "malformed", "got": event }
  end
from in into validate;

create stream validate;
create stream not_ok;

select event from validate where present event.ok into out/ok;
select event from validate where absent event.ok into out/not_ok;
```

## Run vector and tremor side by side

Run vector in a terminal

```bash
$ vector -c etc/vector/vector.toml
```

Run tremor in a terminal

```bash
$ tremor-server -q etc/tremor/logic.trickle -c etc/tremor/tremor.yaml
```

## Results

We should see logs generated in the bash script being appended into an
`input.log` logfile. Vector tails this file and forward the data to
tremor. Tremor checks to see if the data is well-formed JSON and that
it is valid, and then computes the lag.

```text
tremor version: 0.7.3
rd_kafka version: 0x000000ff, 1.3.0
Listening at: http://0.0.0.0:9898
{"ok":{"timestamp":"2020-03-04T11:41:21.753155Z","file":"input.log","host":"ALT01827","message":"{\"application\": \"test\", \"date\":  1583322081543975000 , \"message\": \"demo\"}","elapsed_ms":210}}
{"ok":{"timestamp":"2020-03-04T11:41:22.810429Z","file":"input.log","host":"ALT01827","message":"{\"application\": \"test\", \"date\":  1583322082558827000 , \"message\": \"demo\"}","elapsed_ms":252}}
{"ok":{"timestamp":"2020-03-04T11:41:23.859159Z","file":"input.log","host":"ALT01827","message":"{\"application\": \"test\", \"date\":  1583322083577210000 , \"message\": \"demo\"}","elapsed_ms":282}}
```

## Notes

No effort was made in this integration solution to tune vector or tremor.

For further information on [vector](https://vector.dev/) and [tremor](https://tremor.rs)
consult their respective web sites, documentation and references.

## Glossary

Vector uses the term `source` and `sink` for input to vector and outputs from vector.
Tremor uses the term `onramp` and `offramp` for ingress to tremor and egress from tremor.

In this integration we deployed vector and tremor as sidecars so that we can leverage
file based log events in tremor.

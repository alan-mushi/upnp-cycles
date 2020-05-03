List UPNP IGD port mappings at scale.

Some awfully configured UPNP servers with Internet Gateway Device (IGD) profile
allow anyone to list/add port mappings to redirect traffic, it's [not new](https://www.blackhat.com/presentations/bh-usa-08/Squire/BH_US_08_Squire_A_Fox_in_the_Hen_House%20White%20Paper.pdf).
I wondered if it was still relevant more than 10 years later (and if some
mappings were chained to create circuits).

This a first non-tutorial oriented project in Elixir. It's a somewhat good
training ground for getting acquainted with the language. It works as is but
many improvements could be made.

# "Spec Sheet"

0. Explore and have fun with Elixir and get a feel for what works
1. Use long running Erlang processes and make a client/server kind of thing
2. Be mindful of not shooting ourselves in the foot security-wise
3. Get UPNP+IGD devices from [Shodan](shodan.io) (because the cool kids are all about it)
4. Be able to replay as many (or as little) hosts through the various stages (see below)
5. Store everything, for debugging and replay
6. Adopt the "Keep calm and carry on" attitude towards errors or unexpected "stuff"
7. Tests and logs
8. Use cool-looking things like [Broadway](https://hexdocs.pm/broadway/Broadway.html), [Flow](https://hexdocs.pm/flow/Flow.html) and [GenStage](https://hexdocs.pm/gen_stage/GenStage.html)

# How it works

## Bird's eye view

1. Use Shodan's REST API to get possible listening hosts (search term was "igd")
2. Fetch the XML service definition for IGD
3. List open ports
4. Check if destination ports for the mappings expose UPNP+IGD and loop to 2.

## Under the hood

As a side note, the application is called `Shodan` for historical reasons...
and I did not make time to rename it :)

**TODO**

# Running the thing

The client and server each have their own Erlang node, respectively at
`client@127.0.0.1` and `shodan@127.0.0.1`.

## Setup

0. Mix

```
$ mix clean ; mix deps.clean --all
$ mix deps.get ; mix deps.compile ; mix compile
```

1. PostgreSQL

```
$ sudo ./start_pg.sh
postgres

$ mix ecto.drop ; mix ecto.create ; mix ecto.migrate
The database for Shodan.Repo has been dropped
The database for Shodan.Repo has been created

23:49:59.578 [info]  == Running 20200606115112 Shodan.Repo.Migrations.Init.change/0 forward

23:49:59.579 [info]  create table hosts

23:49:59.584 [info]  create table processor_fragments

23:49:59.589 [info]  == Migrated 20200606115112 in 0.0s
```

2. Set Shodan's API key in `config/secrets.exs`

## Tests

Mock Shodan REST API (in Python3) for trying out everything limit related without burning your API key:

```
$ cd shodan_mock_api
$ . bin/activate
(shodan_mock_api) $ ./run_mock_api.sh
```

The tests are here for the small stuff, full scale integration tests would be
annoying to do and were therefore "tested" :x

```
$ mix test # or "mix test --include network" for network tests
```

## Run

Server:

```
$ mix distillery.release.clean
$ mix distillery.release
$ _build/dev/rel/shodan/bin/shodan console
```

Log file is there: `_build/dev/rel/shodan/logs/all_levels-*.log`

Client:

Kick it all off:

```
$ elixir --cookie 'COOKIE_FROM_RELEASE_CONFIG' \
	--name 'client@127.0.0.1' \
	-r ./lib/command_client.exs \
	-e 'CommandClient.search_all_query("igd")'
```

Let it run...

List identified port mappings:

```
$ elixir --cookie 'COOKIE_FROM_RELEASE_CONFIG' \
	--name 'client@127.0.0.1' \
	-r ./lib/command_client.exs \
	-e 'CommandClient.pretty_print(:list_mapped_ports)'
```

# The End.

Very very few hosts have UPNP+IGD exposed. So the project's premise is moot.

It was fun to use Elixir though.

# Ressources & Docs

https://www.blackhat.com/presentations/bh-usa-08/Squire/BH_US_08_Squire_A_Fox_in_the_Hen_House%20White%20Paper.pdf

https://tools.ietf.org/html/rfc6970

https://tools.ietf.org/id/draft-bpw-pcp-upnp-igd-interworking-01.html

https://developer.shodan.io/api

https://github.com/jsharp6968/UPnPwn

https://github.com/tenable/upnp_info/blob/master/upnp_info.py

https://github.com/flyte/upnpclient

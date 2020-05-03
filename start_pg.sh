#!/bin/bash

docker run --name postgres -d \
	-e POSTGRES_USER=postgres \
	-e POSTGRES_PASSWORD=postgres \
	-e POSTGRES_DB=shodan \
	-e PGDATA=/var/lib/postgresql/data/pgdata \
	-v $(pwd)/pg_data:/var/lib/postgresql/data \
	-p 5432:5432 \
	postgres 2>/dev/null || docker start postgres

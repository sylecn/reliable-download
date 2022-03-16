all: api client
build: dist
dist:
	make -C rd-api dist
	make -C rd-client dist
api:
	make -C rd-api upload
client:
	make -C rd-client upload
.PHONY: all build api client

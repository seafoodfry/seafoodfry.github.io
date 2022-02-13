APP := blog

all: build
	docker run -it -p 4000:4000 blog

debug-network: build
	docker run -it --network=host blog

build:
	docker build -t $(APP) .

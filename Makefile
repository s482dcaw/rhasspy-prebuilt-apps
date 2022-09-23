.PHONY: build dist

all: amd64 arm64 armv7

amd64:
	docker buildx build . --platform linux/amd64 --output type=local,dest=dist

arm64:
	docker buildx build . --platform linux/arm64 --output type=local,dest=dist

armv7:
	docker buildx build . --platform linux/arm/v7 --output type=local,dest=dist

clean:
	docker system prune -a


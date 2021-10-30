VERSION ?= 2021-10-21
CLIENT_VERSION ?= 2021-02-13
HTTP_SERVER_ORIGIN ?= (src\.quicklisp\.org\|beta\.quicklisp\.org)
HTTP_SERVER ?= localhost:8000
ROSWELL ?= ros
GH_OWNER ?= roswell
GH_REPO ?= quicklisp
include .env
export $(shell sed 's/=.*//' .env)

all: download-archives root/dist/quicklisp-versions.txt setversion

httpd:
	cd root;python3 -m http.server &

latest-version:
	$(eval VERSION := $(shell curl -L -f -s https://github.com/$(GH_OWNER)/$(GH_REPO)/releases/download/dist/quicklisp.txt |grep "^version:" |sed -E "s/^[^ ]* //g"))
	@echo "set version $(VERSION)"

setversion: root/dist/quicklisp/$(VERSION)
	cp root/dist/quicklisp/$(VERSION)/distinfo.txt root/dist/quicklisp.txt

size: root/dist/quicklisp/$(VERSION)/releases.tx show
	@echo -n "archives(byte)="
	@cat $< | grep -v '^#' | awk -v 'OFS= ' '{sum += $$3} END { print sum }'

versions: root/dist/quicklisp-versions.txt
	cat $< | sed -E 's#^([^ ]*) .*#\1#g'

quicklisp: 
	curl -f -L https://github.com/quicklisp/quicklisp-client/archive/refs/tags/version-$(CLIENT_VERSION).tar.gz > qlclient.tgz
	tar xf qlclient.tgz
	rm qlclient.tgz
	mv quicklisp-client-version-$(CLIENT_VERSION) $@

quicklisp/local-init/initial-dist.lisp: quicklisp
	mkdir quicklisp/local-init
	echo '(defparameter quicklisp:*initial-dist-url* "http://$(HTTP_SERVER)/dist/quicklisp.txt")' > $@

# for test setup client
quicklisp/dist: quicklisp/local-init/initial-dist.lisp
	$(ROSWELL) +Q -l quicklisp/setup.lisp

clean:
	rm -rf root quicklisp upload

root/dist/quicklisp/$(VERSION):
	VERSION=$(VERSION) make \
		root/dist/quicklisp/$(VERSION)/systems.txt \
		root/dist/quicklisp/$(VERSION)/releases.txt \
		root/dist/quicklisp/$(VERSION)/distinfo.txt \
	|| rm -rf root/dist/quicklisp/$(VERSION)

update-server-info:
	rm -f \
		root/dist/quicklisp/$(VERSION)/distinfo.txt \
		root/dist/quicklisp-versions.txt
	HTTP_SERVER=$(HTTP_SERVER) VERSION=$(VERSION) make \
		root/dist/quicklisp/$(VERSION)/distinfo.txt \
		root/dist/quicklisp-versions.txt

%.txt: %.tx
	cat $< | sed -E "s|$(HTTP_SERVER_ORIGIN)|$(HTTP_SERVER)|g" >$@

root/dist/quicklisp-versions.tx:
	curl -f -L -s --create-dirs --output $@ https://github.com/$(GH_OWNER)/$(GH_REPO)/releases/download/dist/quicklisp-versions.tx
root/dist/quicklisp/$(VERSION)/distinfo.tx:
	curl -f -L -s --create-dirs --output $@  https://github.com/$(GH_OWNER)/$(GH_REPO)/releases/download/$(VERSION)/distinfo.tx
root/dist/quicklisp/$(VERSION)/systems.txt: root/dist/quicklisp/$(VERSION)/distinfo.tx
	curl -f -L -s --create-dirs --output $@  https://github.com/$(GH_OWNER)/$(GH_REPO)/releases/download/$(VERSION)/systems.txt
root/dist/quicklisp/$(VERSION)/releases.tx: root/dist/quicklisp/$(VERSION)/distinfo.tx
	curl -f -L -s --create-dirs --output $@ https://github.com/$(GH_OWNER)/$(GH_REPO)/releases/download/$(VERSION)/releases.tx

download-archives: root/dist/quicklisp/$(VERSION)
	cat $</releases.tx | \
	grep -v '^#' | \
	awk -v 'OFS= ' '{print $$2}'| \
	sed -E "s#(^http://[^/]+/)(.+)\$$#root/\2#g" | \
	xargs -I {} echo "VERSION=$(VERSION) make -s {}"|sh

%.tgz:
	@echo $@ | sed -E "s#root/archive/[^/]+/(.+)\$$#curl -f -L -s --create-dirs --output $@ https://github.com/$(GH_OWNER)/$(GH_REPO)/releases/download/\1#g" | sh
	@echo $@ | sed -E "s#root/archive/[^/]+/(.+)\$$#cat root/dist/quicklisp/$(VERSION)/releases.tx|grep \1#g"|sh| \
		awk -v OFS=' ' '{print $$4}'| \
		sed -E "s#(.+)#\1  $@#g"| md5sum -c

check-md5: root/dist/quicklisp/$(VERSION)
	@cat $</releases.tx | \
	grep -v '^#' | \
	awk -v OFS=' ' '{print $$2,$$4}'| \
	sed -E "s#(^http://[^/]+/)([^ ]+) ([^ ]+)#\\3  root/\\2#g" | \
	md5sum -c | \
	grep -v "OK$$"

download-all:
	@make -s versions | \
	sed -E "s/ .*\$$//g"| \
	xargs -I {} echo "VERSION={} make all"|sh

# for CI
upload:
	ros install snmsts/sn.github roswell/sbcl_bin
	ros build upload.ros

fetch-upload: upload
	@echo fetch-upload $(FILE)
	@rm -f $(FILE)
	@#fetch
	@echo $(FILE) | sed -E "s#root/archive/(.+)\$$#curl -f -L -s --create-dirs --output $(FILE) http://beta.quicklisp.org/archive/\1#g"|sh
	@#upload
	@echo $(FILE) | sed -E "s#root/archive/([^/]+)/([^/]+)/.*\$$#./upload upload $(GH_OWNER) $(GH_REPO) \2 $(FILE) #g"|sh

check-md5-all:
	@make -s versions | \
	sed -E "s/ .*\$$//g"| \
	xargs -I {} echo "VERSION={} make -s check-md5"|sh

download-tx:
	curl -f -L -s --create-dirs --output root/quicklisp/$(VERSION)/releases.tx http://beta.quicklisp.org/dist/quicklisp/$(VERSION)/releases.txt
	curl -f -L -s --create-dirs --output root/dist/quicklisp/$(VERSION)/systems.txt http://beta.quicklisp.org/dist/quicklisp/$(VERSION)/systems.txt
	curl -f -L -s --create-dirs --output root/dist/quicklisp/$(VERSION)/distinfo.tx http://beta.quicklisp.org/dist/quicklisp/$(VERSION)/distinfo.txt

upload-tx:
	./upload upload $(GH_OWNER) $(GH_REPO) $(VERSION) root/dist/quicklisp/$(VERSION)/distinfo.tx
	./upload upload $(GH_OWNER) $(GH_REPO) $(VERSION) root/dist/quicklisp/$(VERSION)/releases.tx
	./upload upload $(GH_OWNER) $(GH_REPO) $(VERSION) root/dist/quicklisp/$(VERSION)/systems.txt

mirror-tx:
	echo mirror $(VERSION)
	VERSION=$(VERSION) make root/dist/quicklisp/$(VERSION) \
	|| VERSION=$(VERSION) make download-tx upload-tx

mirror-all-tx:
	@make -s versions | \
	sed -E "s/ .*\$$//g"| \
	xargs -I {} echo "VERSION={} make -s mirror-tx"|sh

mirror-versions: root/dist/quicklisp-versions.tx
	mv root/dist/quicklisp-versions.tx root/dist/quicklisp-versions.tx.bak
	curl -f -L -s --create-dirs --output root/dist/quicklisp-versions.tx http://beta.quicklisp.org/dist/quicklisp-versions.txt
	diff -u root/dist/quicklisp-versions.tx root/dist/quicklisp-versions.tx.bak \
	|| ./upload upload $(GH_OWNER) $(GH_REPO) dist root/dist/quicklisp-versions.tx
	rm -f root/dist/quicklisp-versions.tx.bak

mirror-quicklisp: setversion
	./upload upload $(GH_OWNER) $(GH_REPO) dist root/dist/quicklisp.txt

mirror-archives: download-archives
	@make -s check-md5 | \
	sed -E "s/^(.*):[^:]*\$$/\1/g" | \
	xargs -I {} echo "FILE={} make fetch-upload"|sh

master-version:
	$(eval VERSION := $(shell curl -f -s http://beta.quicklisp.org/dist/quicklisp.txt |grep "^version:" |sed -E "s/^[^ ]* //g"))
	@echo "set version $(VERSION)"

show:
	@echo version=$(VERSION)
	@echo pwd=$(shell pwd)

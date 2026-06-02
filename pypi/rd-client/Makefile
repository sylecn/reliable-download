VERSION := $(shell grep 'cliVersion =' ../../lib/RD/CliVersion.hs | cut -d'"' -f2)
TWINE := python3 -m twine
RD_CLIENT_ARTIFACT := ../../build/rd
INSTALLED_REQUESTS_VERSION := $(shell python3 -c 'import requests; print(requests.__version__)')

default:
	@echo "usage: make [dist|install|upload]"
bootstrap:
	@python3 -c 'import readme_renderer' || python3 -m pip install --user readme_renderer
	@python3 -c 'import wheel' || python3 -m pip install --user wheel
	@python3 -c 'import twine' || python3 -m pip install --user twine
	if dpkg --compare-versions $(INSTALLED_REQUESTS_VERSION) lt 2.32.0; then \
		@echo "upgrading python3 requests" ; \
		@python3 -m pip install --user -U requests ; \
	fi
dist: bootstrap
	if [ -f $(RD_CLIENT_ARTIFACT) ]; then \
		install $(RD_CLIENT_ARTIFACT) rdclient/ ; \
	else \
		cp -u `stack path --local-install-root`/bin/rd rdclient/ ; \
	fi
	rm -rf dist/*
	python3 setup.py -q bdist_wheel --universal
	$(TWINE) check --strict dist/*
upload: dist
	$(TWINE) upload -u __token__ -p $(RD_CLIENT_TWINE_TOKEN) dist/*
testupload: dist
	env TWINE_PASSWORD=XVgnIVGGFjlMRxDV $(TWINE) upload --repository-url https://test.pypi.org/legacy/ dist/*
install: dist
	if which pipx; then \
		pipx install dist/rd_api-$(VERSION)-py2.py3-none-any.whl ; \
	else \
		python3 -m pip install --user dist/rd-$(VERSION)-py2.py3-none-any.whl ; \
	fi
.PHONY: default twine dist upload install

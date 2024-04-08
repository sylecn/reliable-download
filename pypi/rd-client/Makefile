VERSION := $(shell grep 'version:' ../../package.yaml | cut -d':' -f2 | tr -d ' ')

default:
	@echo "usage: make [dist|install|upload]"
bootstrap:
	if ! python3 -c 'import readme_renderer'; then python3 -m pip install --user readme_renderer ; fi
	test -f ~/.local/bin/wheel || python3 -m pip install --user wheel
	test -f ~/.local/bin/twine || python3 -m pip install --user twine
dist: bootstrap
	cp -u `stack path --local-install-root`/bin/rd rdclient/
	rm -rf dist/*
	python3 setup.py -q bdist_wheel --universal
	~/.local/bin/twine check --strict dist/*
upload: dist
	~/.local/bin/twine upload -u __token__ -p $(RD_CLIENT_TWINE_TOKEN) dist/*
testupload: dist
	env TWINE_PASSWORD=XVgnIVGGFjlMRxDV ~/.local/bin/twine upload --repository-url https://test.pypi.org/legacy/ dist/*
install: dist
	python3 -m pip install --user dist/rd-$(VERSION)-py2.py3-none-any.whl
.PHONY: default twine dist upload install

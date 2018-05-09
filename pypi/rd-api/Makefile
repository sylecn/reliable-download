VERSION := $(shell grep 'version:' ../../package.yaml | cut -d':' -f2 | tr -d ' ')

default:
	@echo "usage: make [dist|install|upload]"
bootstrap:
	test -f ~/.local/bin/wheel || python3 -m pip install --user wheel
	test -f ~/.local/bin/twine || python3 -m pip install --user twine
dist: bootstrap
	cp -u `stack path --local-install-root`/bin/rd-api rdapi/
	rm -rf dist/*
	python3 setup.py -q bdist_wheel --universal
upload: dist
	~/.local/bin/twine upload dist/*
testupload: dist
	~/.local/bin/twine upload --repository-url https://test.pypi.org/legacy/ dist/*
install: dist
	python3 -m pip install --user dist/rd_api-$(VERSION)-py2.py3-none-any.whl
.PHONY: default twine dist upload install

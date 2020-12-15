docs: FORCE
	doxygen Doxyfile
	$(MAKE) -C docs/latex
	@echo
	@echo
	@echo "==="
	@echo "Documentation generated in docs/"
	@echo "==="
	@echo
	@echo

tests: FORCE
	python3 pmfuzz-tests.py

clean:
	rm -rf docs

FORCE: ;

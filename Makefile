all        :; forge build
build      :; forge clean && forge build
.PHONY: test
test       :; ./scripts/forge_test.sh --v=$(v) --mt=$(mt) --mc=$(mc)
gas        :; ./scripts/forge_test.sh --v=$(v) --mt=$(mt) --mc=$(mc) gas-report
coverage   :; forge coverage --fork-url=${ETH_RPC_URL}
gen-report :; forge coverage --fork-url=${ETH_RPC_URL} --report lcov && genhtml lcov.info --output-directory docs/coverage-report
clean      :; forge clean

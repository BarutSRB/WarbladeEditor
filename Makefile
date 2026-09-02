GODOT ?= godot
RELEASE_VERSION ?= 1.0.0
PROJECT := $(CURDIR)
BUILD := $(PROJECT)/build
PARSER := $(PROJECT)/Parser
GODOT_TEST := $(PROJECT)/tools/run_godot_test.sh

.PHONY: verify release-preflight source-version-verify diff-check test-contract-versions test-gap-matrix parse test-parser test-assets test-presentation test-content test-content-catalog test-letter-awards test-endgame-tally test-profile-locks test-time-trial test-hurry-up test-shop-save test-lvd test-swd test-weapons test-sprites test-difficulty test-endless-evidence test-fidelity test-rng test-sim test-first-five-sim test-bonus-contract test-boss-contract test-ordnance-contract test-ordnance-runtime test-retail-big-boss test-level-fifty test-level-seventy-four-public test-level-seventy-five test-level-one-hundred test-campaign-terminal test-endless test-letter-awards test-endgame-tally test-profile-locks test-campaign-twenty-five test-campaign-thirty test-campaign-thirty-five test-campaign-forty-nine test-campaign-fifty test-campaign-sixty-two test-campaign-beyond-one-hundred test-campaign-one-hundred test-campaign-matrix test-campaign-matrix-solo test-campaign-matrix-coop test-campaign-ninety-five-one-hundred test-gem-drop test-bonus-modes test-classic-levels test-levels-six-ten test-levels-eleven-twenty test-levels-twenty-one-twenty-four test-levels-twenty-six-thirty test-levels-thirty-one-thirty-five test-levels-thirty-six-forty-nine test-levels-fifty-one-sixty-two test-levels-sixty-three-one-hundred test-hit-masks test-net test-nat test-client test-lobby lobby-build lobby-test lobby-smoke lobby-run lobby-release lobby-deploy lobby-admin test-talents test-audio test-integration test-host-join test-packaged-runtime-smoke presentation-smoke pack-validate run-pack export-presentation-smoke export-client-runtime-smoke export-server-runtime-smoke export-runtime-smoke export-architecture-verify export-codesign-verify export-version-verify export-debug export-release run run-a run-b server harness

verify: release-preflight test-contract-versions test-gap-matrix parse test-parser test-assets test-presentation test-content test-content-catalog test-time-trial test-hurry-up test-shop-save test-lvd test-swd test-weapons test-sprites test-difficulty test-endless-evidence test-fidelity test-rng test-sim test-first-five-sim test-bonus-contract test-boss-contract test-ordnance-contract test-ordnance-runtime test-retail-big-boss test-level-seventy-four-public test-campaign-terminal test-endless test-letter-awards test-endgame-tally test-profile-locks test-campaign-twenty-five test-campaign-thirty test-campaign-thirty-five test-campaign-forty-nine test-campaign-fifty test-campaign-sixty-two test-campaign-beyond-one-hundred test-campaign-matrix test-bonus-modes test-classic-levels test-hit-masks test-net test-client test-lobby test-talents test-audio test-integration test-host-join test-packaged-runtime-smoke presentation-smoke

release-preflight: source-version-verify diff-check

source-version-verify:
	python3 "$(PROJECT)/tools/source_version_verify.py" --expected "$(RELEASE_VERSION)"
	python3 "$(PROJECT)/tools/source_version_verify_test.py"

diff-check:
	git diff --check

test-contract-versions:
	python3 "$(PROJECT)/tools/gap_language_check.py" --versions-only

test-gap-matrix:
	python3 "$(PROJECT)/tools/gap_language_check.py"
	python3 "$(PROJECT)/tools/gap_language_check_test.py"

parse:
	GODOT="$(GODOT)" "$(GODOT_TEST)" --editor-parse

test-parser:
	cd "$(PARSER)" && python3 -m unittest discover -s tests -v

test-assets:
	python3 "$(PROJECT)/tools/extract_original_assets.py" --check

test-presentation:
	python3 "$(PROJECT)/tools/presentation_manifest.py" --check
	python3 "$(PROJECT)/tools/presentation_manifest_test.py"

test-content:
	python3 "$(PROJECT)/tools/validate_content.py"

test-content-catalog:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_content_catalog.gd

test-lvd:
	python3 "$(PROJECT)/tools/lvd_roundtrip_test.py"

test-swd:
	python3 "$(PROJECT)/tools/swd_roundtrip_test.py"
	python3 "$(PROJECT)/tools/swd_content_extract.py" --check

test-weapons:
	python3 "$(PROJECT)/tools/weapon_runtime_test.py"
	python3 "$(PROJECT)/tools/weapon_runtime_extract.py" --check

test-sprites:
	python3 "$(PROJECT)/tools/sprite_atlas_test.py"
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/shared/test_sprite_frame_catalog_v3.gd

test-difficulty:
	python3 "$(PROJECT)/tools/difficulty_rules_test.py"
	python3 "$(PROJECT)/tools/difficulty_rules.py" --check

test-fidelity:
	python3 "$(PROJECT)/tools/first_five_runtime_extract.py" --check

test-rng:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_deterministic_rng.gd

test-sim:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_game_simulation.gd

test-first-five-sim:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_first_five_fidelity.gd

test-bonus-contract:
	python3 "$(PROJECT)/tools/bonus_modes_extract.py" --check
	python3 "$(PROJECT)/tools/bonus_modes_test.py"

test-boss-contract:
	python3 "$(PROJECT)/tools/boss_contract_extract.py" --check
	python3 "$(PROJECT)/tools/boss_contract_test.py"

test-ordnance-contract:
	python3 "$(PROJECT)/tools/ordnance_contract_extract.py" --check
	python3 "$(PROJECT)/tools/ordnance_contract_test.py"

test-ordnance-runtime:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_ordnance_runtime.gd

test-retail-big-boss: test-level-fifty test-level-seventy-five test-level-one-hundred
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_retail_big_boss.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_retail_big_boss_effect_runtime.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_level_twenty_five_boss_integration.gd

test-level-fifty:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_level_fifty_boss_integration.gd

test-level-seventy-four-public:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_level_seventy_four_public_completion.gd

test-level-seventy-five:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_level_seventy_five_boss_integration.gd

test-level-one-hundred:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_level_one_hundred_boss_integration.gd

test-campaign-terminal:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_terminal_contract.gd

test-endless:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_endless_progression.gd

test-campaign-beyond-one-hundred:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_beyond_one_hundred.gd

test-endless-evidence:
	python3 "$(PROJECT)/tools/endless_progression_test.py"
	python3 "$(PROJECT)/tools/endless_progression_extract.py" --check

test-letter-awards:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_letter_awards.gd
	python3 "$(PROJECT)/tools/letter_award_test.py"
	python3 "$(PROJECT)/tools/letter_award_extract.py" --check

test-endgame-tally:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_endgame_tally.gd
	python3 "$(PROJECT)/tools/game_bonus_tally_test.py"
	python3 "$(PROJECT)/tools/game_bonus_tally_extract.py" --check

test-profile-locks:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_profile_locks.gd
	python3 "$(PROJECT)/tools/profile_lock_test.py"
	python3 "$(PROJECT)/tools/profile_lock_extract.py" --check

test-time-trial:
	python3 "$(PROJECT)/tools/time_trial_extract.py" --check
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_time_trial.gd

test-hurry-up:
	python3 "$(PROJECT)/tools/hurry_up_test.py"
	python3 "$(PROJECT)/tools/hurry_up_extract.py" --check
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_hurry_up.gd

test-shop-save:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_shop_save.gd

test-campaign-twenty-five:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_twenty_five.gd

test-campaign-thirty-five:
	CAMPAIGN_END_LEVEL=35 GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-thirty:
	CAMPAIGN_END_LEVEL=30 GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-forty-nine:
	CAMPAIGN_END_LEVEL=49 GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-fifty:
	CAMPAIGN_END_LEVEL=50 GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-sixty-two:
	CAMPAIGN_END_LEVEL=62 GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-one-hundred:
	CAMPAIGN_END_LEVEL=100 GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-matrix: test-campaign-matrix-solo test-campaign-matrix-coop

test-campaign-matrix-solo:
	CAMPAIGN_END_LEVEL=100 CAMPAIGN_MODE=solo GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-matrix-coop:
	CAMPAIGN_END_LEVEL=100 CAMPAIGN_MODE=coop GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_campaign_through_thirty.gd

test-campaign-ninety-five-one-hundred:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_ninety_five_to_one_hundred_public_campaign.gd

test-gem-drop:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_gem_drop.gd

test-bonus-modes: test-gem-drop
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_memory_station.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_meteor_storm.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_bonus_mode_integration.gd

test-classic-levels: test-level-fifty
	python3 "$(PROJECT)/tools/classic_levels_extract.py" --check
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_level_eight_bonus.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_six_to_ten.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_eleven_to_twenty.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_twenty_one_to_twenty_four.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_twenty_six_to_thirty.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_thirty_one_to_thirty_five.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_thirty_six_to_forty_nine.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_fifty_one_to_sixty_two.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_sixty_three_to_one_hundred.gd

test-levels-six-ten: test-classic-levels

test-levels-eleven-twenty: test-classic-levels

test-levels-twenty-one-twenty-four: test-classic-levels

test-levels-twenty-six-thirty: test-classic-levels

test-levels-thirty-one-thirty-five: test-classic-levels

test-levels-thirty-six-forty-nine:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_thirty_six_to_forty_nine.gd

test-levels-fifty-one-sixty-two:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_fifty_one_to_sixty_two.gd

test-levels-sixty-three-one-hundred:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_levels_sixty_three_to_one_hundred.gd

test-hit-masks:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_hit_masks.gd

test-net:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/net/test_protocol.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/net/test_nat_traversal.gd

# Hole punching and rendezvous mechanics on loopback (seconds).
test-nat:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/net/test_nat_traversal.gd

test-client:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/client/run_client_tests.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/client/test_level_twenty_presentation.gd

test-talents:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/sim/test_talent_start_state.gd

test-lobby: lobby-build
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/client/test_lobby_client.gd
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/client/test_lobby_transport.gd

# The Rust lobby server (identity, lobby list, global chat, talents,
# rendezvous). lobby-smoke spawns a debug build on ports 17400/17401 with a
# temporary database and drives it with tools/lobby_smoke.py.
LOBBY := $(PROJECT)/lobby-server
DROPLET ?= root@68.183.194.133
# rustup's stable toolchain bin dir; the PATH cargo/rustc are Homebrew's standalone Rust.
STABLE_BIN = $(shell dirname "$$(rustup which cargo --toolchain stable)")
lobby-build:
	cd "$(LOBBY)" && cargo build

lobby-test:
	cd "$(LOBBY)" && cargo test

lobby-smoke: lobby-build
	python3 "$(PROJECT)/tools/lobby_smoke.py" --spawn "$(LOBBY)/target/debug/warblade-lobby" --talents "$(PROJECT)/content/talents.json"

lobby-run:
	cd "$(LOBBY)" && WB_WS_BIND=127.0.0.1:7400 WB_UDP_BIND=127.0.0.1:7401 WB_ADMIN_BIND=127.0.0.1:7402 WB_ADMIN_TOKEN=dev-admin-token-0123456789 WB_DB_PATH="$(LOBBY)/dev-lobby.db" WB_TALENTS_PATH="$(PROJECT)/content/talents.json" cargo run

# Release build for the droplet (Linux x86_64, static musl) and deployment.
# One-time on the Mac: cargo install --locked cargo-zigbuild and
# rustup target add x86_64-unknown-linux-musl --toolchain stable. The build runs on
# rustup's stable toolchain (the PATH cargo is Homebrew's). DROPLET defaults to the live droplet.
lobby-release:
	cd "$(LOBBY)" && PATH="$(STABLE_BIN):$$PATH" cargo zigbuild --release --target x86_64-unknown-linux-musl

lobby-deploy:
	DROPLET="$(DROPLET)" sh "$(LOBBY)/deploy/deploy.sh"

# Owner statistics: tunnels the droplet's loopback admin listener to this
# Mac and opens it. Usage: make lobby-admin (override with DROPLET=user@host).
lobby-admin:
	@echo "Opening http://127.0.0.1:7402/admin through an ssh tunnel to $(DROPLET); press Ctrl+C to close it."
	(sleep 2 && open "http://127.0.0.1:7402/admin") &
	ssh -N -L 7402:127.0.0.1:7402 "$(DROPLET)"

test-audio:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/client/test_audio_director.gd

test-integration:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/integration/run_network_integration.gd

# Host/join over loopback with a real publicly bound sidecar (about ten seconds).
test-host-join:
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/integration/test_host_join_lan.gd

test-packaged-runtime-smoke:
	python3 "$(PROJECT)/tools/packaged_runtime_smoke_test.py"
	GODOT="$(GODOT)" "$(GODOT_TEST)" res://tests/app/test_packaged_client_smoke_boundary.gd

presentation-smoke:
	$(GODOT) --headless --path "$(PROJECT)" -- --presentation-smoke

# Sprite-pack authoring (Tripo pipeline). Not part of `verify`: gen needs
# network + credits and render needs a windowed Godot; pack-validate is the
# offline gate for a finished pack. Usage: make pack-validate PACK=solstice
pack-validate:
	python3 "$(PROJECT)/tools/tripo_pipeline_test.py"
	python3 "$(PROJECT)/tools/tripo_pipeline.py" validate --pack "$(PACK)"
	$(GODOT) --headless --path "$(PROJECT)" -- --pack-smoke --sprite-pack=$(PACK)

run-pack:
	$(GODOT) --path "$(PROJECT)" -- --sprite-pack=$(PACK)

export-presentation-smoke:
	"$(BUILD)/Warblade.app/Contents/MacOS/Warblade Remake" --headless -- --presentation-smoke

export-client-runtime-smoke:
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app"
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app" --end-level 99
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app" --end-level 75
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app" --end-level 62
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app" --end-level 50
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app" --end-level 49
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client --app "$(BUILD)/Warblade.app" --end-level 35
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" client-reject --app "$(BUILD)/Warblade.app" --end-level 4000

export-server-runtime-smoke:
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)"
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)" --end-level 99
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)" --end-level 75
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)" --end-level 62
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)" --end-level 50
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)" --end-level 49
	python3 "$(PROJECT)/tools/packaged_runtime_smoke.py" server --app "$(BUILD)/WarbladeServer.app" --godot "$(GODOT)" --project "$(PROJECT)" --end-level 35

export-runtime-smoke: export-client-runtime-smoke export-server-runtime-smoke

export-architecture-verify:
	lipo "$(BUILD)/Warblade.app/Contents/MacOS/Warblade Remake" -verify_arch x86_64
	lipo "$(BUILD)/Warblade.app/Contents/MacOS/Warblade Remake" -verify_arch arm64
	lipo "$(BUILD)/WarbladeServer.app/Contents/MacOS/Warblade Remake" -verify_arch x86_64
	lipo "$(BUILD)/WarbladeServer.app/Contents/MacOS/Warblade Remake" -verify_arch arm64

export-codesign-verify:
	codesign --verify --deep --strict "$(BUILD)/Warblade.app"
	codesign --verify --deep --strict "$(BUILD)/WarbladeServer.app"

export-version-verify:
	python3 "$(PROJECT)/tools/export_version_verify.py" --expected "$(RELEASE_VERSION)" --app "$(BUILD)/Warblade.app" --app "$(BUILD)/WarbladeServer.app"

export-debug:
	mkdir -p "$(BUILD)"
	$(GODOT) --headless --path "$(PROJECT)" --export-debug "macOS Client" "$(BUILD)/Warblade-debug.app"
	$(GODOT) --headless --path "$(PROJECT)" --export-debug "macOS Server" "$(BUILD)/WarbladeServer-debug.app"

export-release: verify
	mkdir -p "$(BUILD)"
	$(GODOT) --headless --path "$(PROJECT)" --export-release "macOS Client" "$(BUILD)/Warblade.app"
	$(GODOT) --headless --path "$(PROJECT)" --export-release "macOS Server" "$(BUILD)/WarbladeServer.app"
	$(MAKE) export-presentation-smoke export-runtime-smoke export-architecture-verify export-codesign-verify export-version-verify

run:
	$(GODOT) --path "$(PROJECT)"

server:
	$(GODOT) --headless --path "$(PROJECT)" -- --server

# Two clients on one Mac for online smoke tests: separate identity, talent
# cache, and settings files per instance (profiles and saves stay shared).
run-a:
	$(GODOT) --path "$(PROJECT)" -- --profile-suffix=a --window-title=A

run-b:
	$(GODOT) --path "$(PROJECT)" -- --profile-suffix=b --window-title=B

harness:
	$(GODOT) --path "$(PROJECT)" -- --local-two-client-harness

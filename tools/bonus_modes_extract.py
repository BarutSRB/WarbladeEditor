#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

import lvd_decoder
from first_five_runtime_extract import PEImage


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = ROOT / "Game" / "warblade.exe"
DEFAULT_LEVELS = ROOT / "content" / "levels.json"
DEFAULT_OUTPUT = ROOT / "content" / "bonus_modes.json"
DEFAULT_EVIDENCE = ROOT / "docs" / "evidence" / "BONUS_MODES.md"
EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
MODE_THREE_LEVEL_IDS = (8, 16, 24, 33, 41, 49, 58, 66, 74, 83, 91, 99)
VERSION_7_MODE_THREE_LEVEL_IDS = MODE_THREE_LEVEL_IDS[:7]
LEGACY_MODE_THREE_LEVEL_IDS = MODE_THREE_LEVEL_IDS[:6]

REGION_SPECS = (
    ("level8_mode3_loader", 0x0056B12F, 96, "0f508183c34711c37fd0cb78883bfb7db8e1f9d421f28a3fc586a89aadc5aaf6"),
    ("level8_hit_owner_a", 0x005881E4, 64, "3080585ab0bd5d436ed2e7e82eba5e819878cf96b9c4379df99881fc0e19a44c"),
    ("level8_hit_owner_b", 0x00588BA2, 64, "f436bbe62b37251a54cb87aafff89ea44413194f0085ad8d98b3768f738257aa"),
    ("level8_hit_owner_c", 0x00589F55, 64, "ab4d1824aeb622c71c374e618bd9eb27c68d7c31977add0f56673633a06e954d"),
    ("level8_hit_owner_d", 0x0058A34C, 64, "7279b6b29be81e0332d96580f127661dbfcef0f8f75c09994a2214cd9f023dad"),
    ("level8_result_setup", 0x005B147C, 256, "18bf4c934dab89cad452462e436fa91e684f7956daa52a0530ebd12fd48dc533"),
    ("level8_result_expire_reset", 0x005F5062, 400, "05e7d361239c80f99beef53d048510b12e12b94f4eceffc712b916da27c75625"),
    ("level8_perfect_reward", 0x005F5A80, 1360, "4e3a9a245d3e73344f4a14f0c71d56cef265d39c19b8a8a07160d7244db670c9"),
    ("level8_hit_reveal", 0x005F6005, 512, "fa7d71fa6e7769f472ef2bedb1133172fca49cb1a0ac958e4fcfa1c99ce63357"),
    ("level8_progressive_table_init", 0x00774E20, 255, "3a22e65f0e9a9b6deae91116d0c5aecc6b281400dc0e6383fd1b4bec4f053519"),
    ("level8_score_constant_init", 0x007752C6, 180, "c6307e3e4a818676cd191069ed77770e127962b17b5a31aea53fe0a1436fb63d"),
    ("background_selector_1_25", 0x00569D56, 134, "fc90cc7b05c5f66bcd7482393211801717a97cf2e5a0756d1f7a8bbfc94f7ab3"),
    ("ordinary_projectile_audio_slots", 0x00607BE3, 376, "70ff548ff03b50aaa1e877472a5498b92f2f6f3da1618d5391882669c8461015"),
    ("memory_grid_init", 0x005F7AB0, 1360, "04bfa7c6a89270005c66326f6bcabb3133a5ad7301d701e6946dca05f519fcae"),
    ("memory_update_effects", 0x005E16C0, 512, "0bce324c3b00029bb783aad9c538e12b9fd38b4ff48259c95708185ff627b9d6"),
    ("memory_countdown_audio", 0x005E1900, 1024, "7aaa999cc1780ec5e0a1ae5cdee67eacc0cd4251b1bd81a8d19b2b6537940689"),
    ("memory_gem_rewards_and_audio", 0x005E4A51, 1517, "c7616571285e70c835b403117db85f3ab92aec0d585d8f3611efd64d685461c3"),
    ("memory_gem_bell_audio", 0x005E4A51, 57, "41922fcc8057d71a966597bc5079c3a09cfe6e133b75f6fcb82a1cc8f77b0598"),
    ("memory_completion_audio", 0x005E79D4, 86, "7ea9698cc0e22848eecc55cecb083fad68736dc21aa6aadfadf3a79d74593f7b"),
    ("memory_gem_jump_entries", 0x005E8510, 28, "12f177dbff69f04b2c7d4bb0fd85ac37082568b9d76fde7d433842f145ae608e"),
    ("memory_renderer", 0x005FCDC0, 512, "443b948c3bc86bd6fc2741876f28a293c4633d606d1f5d4b475112ffb93fd8b2"),
    ("memory_completion", 0x005AC450, 512, "971939d605186682407abd4ef51fa268633cb8edb1e775d040a561e90868e120"),
    ("meteor_spawn", 0x005F8000, 1584, "f40d482ecac7475d79b06340309eb060cf056b7688f9c3c0858d890eb91e0f69"),
    ("meteor_init", 0x005F8630, 512, "9296654c5be43d418ebabffbaf987b356129b61106ef1e87960efe25cf15e286"),
    ("meteor_update", 0x005F9F60, 512, "b11f50c6b05983af3e21b5bebb4b1a9c3c8e806723b6bc26403905360d10e19c"),
    ("meteor_flyby_audio", 0x005FA140, 192, "0bf672fa5057779855e6da2dc943939262746fae8dc7993022038045d402e4a0"),
    ("meteor_draw", 0x005FC9B0, 1040, "bb8f1c3233459bb7395ae943744b905c70dc8b04aa17e37f95b639756992b409"),
    ("meteor_collision_rewards", 0x005FDA70, 1024, "2da4160e651414614e82d4a807d7bbc8f772708b7f3b26250deea58f878a30e5"),
    ("meteor_collision_audio", 0x005FDED0, 128, "764cacc0297f7eb1353ec30ccf9b07c754e323ff49d3375032fc7c6b8943d149"),
    ("meteor_gem_rewards_and_audio", 0x005FE75D, 5147, "40253318def47ef04d5fcabbbf56ab442009e86d0a5d8a8d6bcb8feff1216d0e"),
    ("meteor_result", 0x005DCD80, 512, "5bfb5868757d056b8b3029f53f3e0c90d39a8e6cd2a82024ffcaa51dbe0741a2"),
    ("gem_drop_deadline_gate", 0x005ACE8E, 60, "e6eb195602498f24a87d1b5fbbdc4d34d2f40f4c3f8ed85b50d9ae682856c69b"),
    ("gem_drop_state18_handler", 0x005B222B, 258, "62cb03a06c858b313565c31d700079a70cd3d7dc1599d1745d3d6af0752324b0"),
    ("gem_drop_frame_render", 0x005DEEF0, 185, "e7ab443a29b5fe8c18ed582bb03d0f8a7a30e80b5e520e13c9482b7c7f75c188"),
    ("gem_drop_player_move_left", 0x005EA250, 899, "872b425f1ad419d83d16b3c06d3effb6b370239b4202b6bed973c63e5e472486"),
    ("gem_drop_player_move_right", 0x005EA6C0, 815, "a8ebfafa0f4d18dde1d0dfd827e83e2bcb40573da4ba6169ccc895d8adb362a8"),
    ("gem_drop_primary_fire_gate", 0x005EBB6E, 159, "12b0a59e48987917a7e880bbb7256916918554d9b193650c4df5c80f7852fca1"),
    ("gem_drop_secondary_state_gate", 0x005EC546, 181, "bc8d330515c778f0f83871b36a45d652b296a6cdc0b528838f87b7c0438579ec"),
    ("gem_drop_cpu_targeting", 0x00583CB0, 365, "c3c2d4fe08de01c0ae736b3d085fb7da5ab3759af0ac2f752c63853090305ae4"),
    ("gem_drop_pan_table_init", 0x00531900, 113, "1b0557b656167e6125f20625db66743282c35b0820196298cf992821d5a10b97"),
    ("gem_drop_sound_pan_wrapper", 0x005334AC, 18, "d0c7b11e2221b4b57b9f9995269196284cd88d6ccb3a44a6ff923e5e52782912"),
    ("gem_drop_shared_pool_reset", 0x0059BB90, 0x544, "441b7581893c157b6274e51fbf872e0798bd2a1cd9049f5cc1e6001c4a8dcbf2"),
    ("gem_drop_init", 0x005F8750, 325, "d7fce75372d4e73d1b349720f02c5a11e7b56406618503b9720ae0b47da8e2ec"),
    ("gem_drop_music", 0x005F8F30, 103, "69362d0a86e677a29def169dc440ef9592c23c2fea8bb710412931b9e4432bda"),
    ("gem_drop_transition_entry", 0x005FED6B, 154, "ac0dc510c8659a35024157465dd874b4058ae5287d6bb0d0609d80aba058b0a9"),
    ("gem_drop_renderer", 0x005FD5B0, 939, "2851ccb82ce65ad070961cd305c3a43018373ab13b0994a2c3785842616248cf"),
    ("gem_drop_collision_rewards", 0x006003C0, 3519, "bb41810aecc82d93917d225935a6e13bcdd430f52effd2b3144379996ace429d"),
    ("gem_drop_update_completion", 0x006014F0, 1601, "47bdf6cf1c854e48c3e180471a64ab8dd7857da8e6c8f3c502cf46c8fec8a036"),
    ("gem_drop_reward_constants", 0x007752C6, 672, "a7581a1077c92d882ec9b038ce2740aa1d9b39a15bc3b7a3511e910668508046"),
    ("rank_voice_load", 0x00535650, 2193, "d3c07199d252ecb91b75a8951738915e012df0ba2c25242ea036f2e8d68cf81b"),
    ("rank_voice_queue_1_32", 0x005F8FE0, 3130, "f70e8fe40cdbbd176ff54b9d189cfe47eb1f342ceb074f2239a22e0ec6f78508"),
)

ASSET_SPECS = {
    "memoryblocks": ("textures/bonus_modes/memoryblocks.tga", 534121, "0222a6a6885ef96cf4aa9b534d8505d31d4f8e062c91cdff407dfdc8086dc2cf", [256, 640]),
    "meteorbonuses": ("textures/bonus_modes/meteorbonuses.tga", 155267, "38dc86def2b0a4784e6e71215185a870520d2825b80f26343f6303ab41c9b4ce", [384, 370]),
    "meteorbonuses_hma": ("textures/bonus_modes/meteorbonuses.hma", 142080, "b44364bebbd194293de3b4654f4a277cef241d6e1da1eadf818ce53a7ffe5a65", [384, 370]),
    "meteormeter2": ("textures/bonus_modes/meteormeter2.tga", 58701, "55e90239d571eaa63e8ade1cb9118f78a3f38053ab8b2efa3147154b6f573d60", [64, 640]),
    "meteors": ("textures/bonus_modes/meteors.png", 547641, "ab5ef22a30e71753f49bf0ba527c6c0ff2d581f48e44db530bb2a0fa196d9659", [624, 717]),
    "meteors_hma": ("textures/bonus_modes/meteors.hma", 447408, "d566c358f6276196f2b3e7666d4949cd8e1818aa970b089496cdbd3f9742a0af", [624, 717]),
    "diamantbig": ("textures/ui/diamantbig.tga", 224373, "3095482e8d7318cad85d930c9a9d5e228f79e5c2b964413b827bd670ab4e2288", [240, 561]),
    "diamantbig_hma": ("textures/ui/diamantbig.hma", 134640, "89278f8d79c3da7fb3375be0bc130ab7b7504f44a7b2375af0c5a116225fb0cb", [240, 561]),
    "memory_music": ("music/memory.mp3", 513344, "76a470bf8da6ecbb3ebe2286ff654b0dbf02ade28a1a036424fafea195165945", None),
    "meteor_music": ("music/meteor.mp3", 1451936, "d8d84c1a1dd912524508449a8dac201f916130ec40df7f3418156457073e8ac5", None),
    "gems_music": ("music/gems.mp3", 909708, "86a42f33ba58c038f62c4a095b89c0ab418ad262190c497759399483a1504aa3", None),
    "harpgliss1_sfx": ("samples/HarpGliss1.mp3", 17296, "2036e2b6ca540141593a8bacce22c9053cb608f318779eabeef5653d1b32dd7c", None),
    "jingles_sfx": ("samples/jingles.mp3", 18348, "20cee89abd4909f467ce69decde7d696797498939459f10dbb00a1fe0f1f857b", None),
    "memorystation_voice": ("voices/rank_0/memorystation.mp3", 14420, "33f9b2ab6503a6bb3ca318a8674a28801ebd0230e8fbbf6e2a17e023ea1186eb", None),
    "meteorstorm_voice": ("voices/rank_0/meteorstorm.mp3", 14106, "450d1cf377d937eb3f27e002043be8784d348fe5028f51fed31ca0165f5c990b", None),
    "bonus_voice": ("voices/rank_0/bonus.mp3", 10345, "332a922df758b5596af0ccce8c68b0039673c82a106d01fbfd5b2f62a5c45e7a", None),
    "gemdrop_voice": ("voices/rank_0/gemdrop.mp3", 10345, "05486de262319e8a4f3fec06b9a5b2005e9265db48b9662f9ffb289b2c103a98", None),
}

RANK_VOICE_SHA256 = {
    "admiral": "d7b003ccd7cca21b0ba3268a73a646ff4de85121e596e138c27e7ffa60c32a48",
    "bronze": "e33bc84715085f9308d55d0bd1efb56b096f566ee8f1ef56b551621b269d38b0",
    "captain": "a76bff237d0d02016bc23a40f482e0e1ad8f75005d60564eb9695e2cf299cd8b",
    "commander": "28f472a3a76bb6deafa4dcbb7f73f152b23ca477b1901d6ad74b28edf42e4c72",
    "congratulations": "e865e4e62ee6033c63a653898d1cea38c92c09e8adc9cd7f7e83228b0346a560",
    "eight": "c8aa49927334529b2d7338429ef6bf254a50b64951c9bbf577a1c97f72480b40",
    "five": "0ed5fe1062a9d0d53f0f9f565ba49e20f6abd8cc4a8eafa2e7a36731f9045149",
    "four": "2da382f80ea73a9c9d3f9bab96af7de3a8bcbe8feebec2b63142550060269427",
    "gold": "f1386fcd57b4b0f5cf16ea6b0d155efa144cc32459c2ac65464fb40a3ee5b752",
    "grandmaster": "b197801088571ce613f7d05396c46eabc83fdae46f3cb89ae19696abe18f8adb",
    "knight": "424f5bdab01272a760ec852c3d48f11f72f8ec2ef92233bab6400b106e0e399a",
    "lieutenant": "8be566aa2f5d9393a4780cfd4f7add9b6424d516b3e3b9d39be57000e42694c5",
    "lord": "52e3efe33ec80642bf60083fbe825ee7a964517f559c17803fdf9bc130c54cab",
    "nine": "33ae60b2eb1ea32387820713be3f5a6e1c37fc65fb7376abf402be10680606ca",
    "one": "50dccf52964001e766b3482e8baafd54e93b72a539cc1da76bb3f77419c30662",
    "overlord": "bfb5766c86af03e8df339f1f491c58d86e506121231f5bb6fa4a32c4c9e71840",
    "rank": "28bed24cb3eda69aa769c36599e9744d45e8c05fafc7f5f318478ce3cc57097b",
    "silver": "467aeb77bddf827e8d698dadc1875c78507bc2101c2d8f19bc9d6d893d4bca69",
    "seven": "777d81b9ec31b609d8eff3453cd957350c661f28e74f151f2a9d2b9bbb7d940b",
    "six": "24226b930255c396b380a24082a1fbc99b06e5a181d442eddd2838bde084910c",
    "star": "d964f70a84c09ddf5a3eb81680b7826a5332a1c98e5caad4a4ffd1a8ea1c8cf7",
    "stars": "a8b3f22414b50f496dbd85a50d94d4d81b15ba31c520fe5c3104cfb62a79fd55",
    "three": "ef19f1661413a5e7081b22ccc5fa933c00dc24042a8c5dd5352a888ac740b659",
    "ten": "e12b6f7b5acb2f4bd1b2e6c5985cda60d8522eb4e38290b0b86d07f420529f48",
    "two": "61521b59c8d610374b42de680157ede054f2134d62dfe19b0c58a8879f1be1ca",
    "warblade": "8eef56b696723793314065d8840b60285f55efd875366c11c5c9da41973b233e",
}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def mode_three_level_aliases(
    levels_path: Path = DEFAULT_LEVELS,
) -> list[dict[str, int]]:
    levels_document = json.loads(levels_path.read_text(encoding="utf-8"))
    levels_version = levels_document.get("version")
    if levels_version not in (5, 6, 7, 8, 9, 10) or levels_document.get(
        "schema"
    ) != f"warblade.levels.v{levels_version}":
        raise ValueError("mode-three extraction requires levels.json v5 through v10")
    levels = levels_document.get("levels")
    expected_level_count = {5: 49, 6: 50, 7: 62, 8: 100, 9: 100, 10: 100}[levels_version]
    expected_mode_three_ids = (
        MODE_THREE_LEVEL_IDS
        if levels_version >= 8
        else VERSION_7_MODE_THREE_LEVEL_IDS
        if levels_version == 7
        else LEGACY_MODE_THREE_LEVEL_IDS
    )
    if (
        not isinstance(levels, list)
        or [level.get("id") for level in levels]
        != list(range(1, expected_level_count + 1))
    ):
        raise ValueError(
            f"mode-three extraction requires ordered levels 1 through {expected_level_count}"
        )
    catalog_mode_three_ids = tuple(
        level["id"]
        for level in levels
        if isinstance(level.get("authored_lvd"), dict)
        and level["authored_lvd"].get("level_mode_id") == 3
    )
    if catalog_mode_three_ids != expected_mode_three_ids:
        raise ValueError("levels.json mode-three membership diverges from retail evidence")

    aliases: list[dict[str, int]] = []
    for level_id in expected_mode_three_ids:
        level = levels[level_id - 1]
        expected_raw_lvd = (
            f"res://assets/original/levels/classic_level_{level_id:03}.lvd"
        )
        if level.get("raw_lvd") != expected_raw_lvd:
            raise ValueError(f"level {level_id} raw LVD path is not canonical")
        raw_lvd_path = ROOT / expected_raw_lvd.removeprefix("res://")
        payload = raw_lvd_path.read_bytes()
        payload_sha256 = _sha256(payload)
        if (
            len(payload) != lvd_decoder.FILE_SIZE
            or level.get("raw_lvd_sha256") != payload_sha256
        ):
            raise ValueError(f"level {level_id} raw LVD SHA-256 pin drift")
        decoded = lvd_decoder.decode_blob(payload, str(raw_lvd_path))
        if lvd_decoder.encode_document(decoded) != payload:
            raise ValueError(f"level {level_id} raw LVD round trip drift")

        decoded_mode = decoded["summary"]["level_mode_id"]
        decoded_target_count = decoded["summary"]["authored_enemy_count"]
        decoded_slot_one_score = decoded["unresolved_tail_array_a"]["raw_words"][0]
        authored = level.get("authored_lvd")
        resources = level.get("enemy_resources")
        if not isinstance(authored, dict) or not isinstance(resources, list):
            raise ValueError(f"level {level_id} is missing authored mode-three facts")
        groups = authored.get("groups")
        if not isinstance(groups, list) or any(
            not isinstance(group, dict) or not isinstance(group.get("enemies"), list)
            for group in groups
        ):
            raise ValueError(f"level {level_id} authored groups are malformed")
        catalog_target_count = sum(len(group["enemies"]) for group in groups)
        slot_one_resources = [
            resource
            for resource in resources
            if isinstance(resource, dict) and resource.get("resource_slot_id") == 1
        ]
        if len(slot_one_resources) != 1:
            raise ValueError(f"level {level_id} must declare one slot-1 enemy resource")
        catalog_slot_one_score = slot_one_resources[0].get("kill_score")
        if (
            decoded_mode != 3
            or authored.get("level_mode_id") != decoded_mode
            or catalog_target_count != decoded_target_count
            or catalog_slot_one_score != decoded_slot_one_score
        ):
            raise ValueError(
                f"level {level_id} mode-three catalog facts diverge from its pinned LVD"
            )
        aliases.append(
            {
                "level_id": level_id,
                "authored_target_count": decoded_target_count,
                "authored_enemy_score": decoded_slot_one_score,
            }
        )
    return aliases


def _verified_regions(image: PEImage) -> list[dict[str, Any]]:
    records = []
    for name, va, size, expected in REGION_SPECS:
        actual = _sha256(image.bytes_at(va, size))
        if actual != expected:
            raise ValueError(f"executable region drift for {name}: {actual}")
        records.append({"name": name, "va": f"0x{va:08x}", "size": size, "sha256": actual})
    return records


def _verified_assets() -> dict[str, Any]:
    records: dict[str, Any] = {}
    for key, (relative, size, expected, dimensions) in ASSET_SPECS.items():
        path = ROOT / "assets" / "original" / relative
        data = path.read_bytes()
        if len(data) != size or _sha256(data) != expected:
            raise ValueError(f"bonus asset drift for {key}")
        record: dict[str, Any] = {
            "path": f"res://assets/original/{relative}",
            "byte_size": size,
            "sha256": expected,
        }
        if dimensions is not None:
            record["dimensions"] = dimensions
        records[key] = record
    return records


def _cue(key: str, padding_ms: int) -> dict[str, Any]:
    return {"key": key, "padding_ms": padding_ms}


def _rank_sequences() -> list[dict[str, Any]]:
    names = [
        "LIEUTENANT", "COMMANDER", "CAPTAIN", "ADMIRAL",
        "ADMIRAL 1 BRONZE STAR", "ADMIRAL 2 BRONZE STARS", "ADMIRAL 3 BRONZE STARS",
        "ADMIRAL 1 SILVER STAR", "ADMIRAL 2 SILVER STARS", "ADMIRAL 3 SILVER STARS",
        "ADMIRAL 1 GOLD STAR", "ADMIRAL 2 GOLD STARS", "ADMIRAL 3 GOLD STARS",
        "WARBLADE KNIGHT", "WARBLADE LORD", "WARBLADE OVERLORD", "WARBLADE GRANDMASTER",
        "WARBLADE GRANDMASTER 1 GOLD STAR", "WARBLADE GRANDMASTER 2 GOLD STARS",
        "WARBLADE GRANDMASTER 3 GOLD STARS",
    ]
    branch: dict[int, list[dict[str, Any]]] = {
        1: [_cue("lieutenant", 50), _cue("rank", 50)],
        2: [_cue("commander", 50), _cue("rank", 50)],
        3: [_cue("captain", 50), _cue("rank", 50)],
        4: [_cue("admiral", 50), _cue("rank", 50)],
    }
    colors = {5: "bronze", 8: "silver", 11: "gold"}
    for start, color in colors.items():
        for offset, number in enumerate(("one", "two", "three")):
            rank = start + offset
            branch[rank] = [
                _cue("admiral", 100), _cue("rank", 50), _cue(number, 5),
                _cue(color, 5), _cue("star" if offset == 0 else "stars", 0),
            ]
    for rank, title in ((14, "knight"), (15, "lord"), (16, "overlord"), (17, "grandmaster")):
        branch[rank] = [_cue("warblade", 20), _cue(title, 50), _cue("rank", 50)]
    for rank, number in ((18, "one"), (19, "two"), (20, "three")):
        branch[rank] = [
            _cue("warblade", 20), _cue("grandmaster", 20), _cue("rank", 50),
            _cue(number, 5), _cue("gold", 5), _cue("star" if rank == 18 else "stars", 0),
        ]
    return [
        {
            "rank": rank,
            "display_name": names[rank - 1],
            "queue": [_cue("congratulations", 100), *branch[rank]],
        }
        for rank in range(1, 21)
    ]


def _rank_voice_assets() -> dict[str, Any]:
    records: dict[str, Any] = {}
    for key, expected in sorted(RANK_VOICE_SHA256.items()):
        path = ROOT / "assets" / "original" / "voices" / "rank_0" / f"{key}.mp3"
        data = path.read_bytes()
        if _sha256(data) != expected:
            raise ValueError(f"rank voice drift for {key}")
        records[key] = {
            "path": f"res://assets/original/voices/rank_0/{key}.mp3",
            "byte_size": len(data),
            "sha256": expected,
            "voice_pack_id": 1,
        }
    return records


def _tile_effects() -> dict[str, Any]:
    effects: dict[int, dict[str, Any]] = {
        0: {"effect_key": "no_effect", "case_address": "not_dispatched"},
        1: {"effect_key": "deadline_delta_applied", "case_address": "0x005e23be", "delta_ms": -15000},
        2: {"effect_key": "timed_score_multiplier", "case_address": "0x005e2400", "multiplier": 2},
        3: {"effect_key": "timed_score_multiplier", "case_address": "0x005e2476", "multiplier": 5},
        4: {"effect_key": "score_applied", "case_address": "0x005e24ec", "base_score": 100},
        5: {"effect_key": "score_applied", "case_address": "0x005e2687", "base_score": 1000},
        6: {"effect_key": "score_applied", "case_address": "0x005e2822", "base_score": 10000},
        7: {"effect_key": "money_doubler", "case_address": "0x005e29bd", "malfunction_threshold": 450000},
        8: {"effect_key": "money_or_score", "case_address": "0x005e2d7a", "amount": 50},
        9: {"effect_key": "money_or_score", "case_address": "0x005e30b4", "amount": 100},
        10: {"effect_key": "money_or_score", "case_address": "0x005e33ee", "amount": 200},
        11: {"effect_key": "deadline_delta_applied", "case_address": "0x005e3728", "delta_ms": 10000},
        12: {"effect_key": "life_armour_or_score", "case_address": "0x005e3770", "fallback_base_score": 1000000},
        19: {"effect_key": "bullet_capacity_or_score", "case_address": "0x005e47df", "fallback_base_score": 25000},
        36: {"effect_key": "extra_speed_or_score", "case_address": "0x005e72f8", "fallback_base_score": 25000},
        37: {"effect_key": "bonus_time_or_score", "case_address": "0x005e75a1", "bonus_time_delta": 5, "fallback_base_score": 25000},
        38: {"effect_key": "money_cap_star", "case_address": "0x005e7829", "star_cap": 10, "expanded_money_cap": 999990},
    }
    for tile_type, bit in zip(range(13, 19), (0x20, 0x10, 0x08, 0x04, 0x02, 0x01)):
        effects[tile_type] = {"effect_key": "rank_marker_or_score", "case_address": f"0x{0x005E3B8B + (tile_type - 13) * 0x20E:08x}", "marker_bit": bit, "base_score": 5000}
    for tile_type in range(20, 24):
        effects[tile_type] = {"effect_key": "no_effect", "case_address": "0x005e79d4"}
    for tile_type in range(24, 31):
        effects[tile_type] = {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500}
    extra_addresses = [0x005E503E, 0x005E5730, 0x005E5E22, 0x005E6514, 0x005E6C06]
    for index, tile_type in enumerate(range(31, 36)):
        effects[tile_type] = {"effect_key": "extra_letter_or_score", "case_address": f"0x{extra_addresses[index]:08x}", "letter_index": index, "duplicate_base_score": 100}
    return {str(key): effects[key] for key in sorted(effects)}


def _legacy_pan_contract() -> dict[str, Any]:
    return {
        "table_base_va": "0x00af6048",
        "table_init_va": "0x00531900-0x00531970",
        "formula": "f32(float(screen_x) * (255.0 / runtime_screen_width))",
        "screen_x_clamp": [0, "runtime_screen_width - 1"],
        "sound_wrapper_va": "0x00533430-0x0053353e",
        "wrapper_behavior": "the selected table float is passed unchanged as argument 4 and then unchanged to BASS_ChannelSetAttribute(channel, 3, value)",
        "godot_normalization": "none is present in the retail executable; any conversion to Godot's -1..1 pan domain is an explicitly documented engine adaptation",
    }


def _gem_drop_contract() -> dict[str, Any]:
    return {
        "trigger": {
            "sources": ["Memory Station gem tile types 24-30", "Meteor Storm gem pickups"],
            "ordinary_display": "G E M   D R O P",
            "super_display": "S U P E R   G E M   D R O P",
            "super_flag_storage": "byte 0x00e11a2d",
            "transition_semantics": "terminal handoff: the originating bonus mode is not restored",
            "source_specific_rng_order": {
                "memory_station": "draw bell frequency first; perform two progress increments/probes; on threshold queue gemdrop, then Gem Drop init runs the RNG-consuming shared reset before its 30 slot draws",
                "meteor_storm": "award the Meteor gem and perform five progress increments/probes; on threshold queue gemdrop and Gem Drop init runs the RNG-consuming shared reset before its 30 slot draws; only after init does the Meteor common tail attempt the ordinary bonus voice and draw bell frequency",
            },
        },
        "intro": {
            "main_state": 18,
            "deadline_ms": 4000,
            "deadline_active_rule": "now < deadline",
            "deadline_equality": "expired",
            "during_intro": [
                "run the standard player input, movement, primary-fire, and common death updates",
                "render the scene, players, effects, UI, and any active Gem Drop slots",
                "suppress the Gem Drop updater and all Gem Drop collision scans",
                "do not advance ordinary projectile pools even though primary fire can allocate into them",
            ],
            "music": {
                "asset": "gems_music",
                "literal": "gems",
                "switch_va": "0x005f8f30-0x005f8f96",
                "skip_guard": "skip the switch only when byte[0x00af787c] == 2 and dword[0x00e11afc] != 0",
                "restore_origin_track": False,
            },
        },
        "player_controller": {
            "runs_during_intro_and_active_play": True,
            "dispatcher_call_va": "0x005b227d",
            "movement": {
                "left_has_priority_over_right": True,
                "speed_step": "min(player_speed * axis_factor, 14.0) * tick_scale",
                "drunk_reverses_horizontal_travel": True,
                "retail_sprite_top_left_x_clamp": [64.0, "runtime_screen_width - 104.0"],
                "normalized_40_pixel_collider_center_x_clamp": [84.0, "runtime_screen_width - 84.0"],
                "bank_step": 0.5,
                "bank_clamp": [0.0, 11.0],
                "inactive_input_recenters_bank": True,
            },
            "primary_fire": {
                "input_call_va": "0x005ebb74",
                "state_suppression_checks_in_order": [9, 10, 11, 20, 17],
                "state_18_suppressed": False,
                "effect": "normal weapon gates and allocation execute; spawned ordinary projectiles are not advanced by the state-18 dispatcher and are discarded by the shared resets",
            },
            "secondary_fire": {
                "input_call_va": "0x005ec54c",
                "state_18_check_va": "0x005ec5b3-0x005ec5ba",
                "state_18_behavior": "take the shared state-10 scroll branch, then jump past the secondary weapon path",
            },
            "cpu_autopilot": {
                "retail_only_route": True,
                "supported_remake_player_routes": False,
                "reason": "the Remake exposes human solo and co-op seats, not the retail demo/CPU control route",
                "state_18_targeting_va": "0x00583cb0-0x00583e1c",
                "slot_scan_order": [0, 9],
                "eligibility": "strict 0 < slot_y < 550 and strict 70 < slot_center_x < runtime_screen_width - 70",
                "selection": "greatest slot_y wins; equal-y ties retain the earlier slot",
                "fire_rng": "RngInt(0,100) once per player update and fire when draw < 4",
            },
        },
        "pool": {
            "slot_count": 10,
            "slot_stride_bytes": 84,
            "base_va": "0x00847398",
            "active_count_storage": "dword 0x00e11a34",
            "source_frame_size": [80, 51],
            "stored_extent_fields": {"vertical_extent": 51, "horizontal_extent": 80},
            "initialization": {
                "all_slots_active": False,
                "remaining_scalar": 2680.0,
                "active_target": 1.0,
                "active_target_growth_per_update": 0.0020000000949949026,
                "rng_per_slot_in_order": [
                    {"kind": "int", "half_open": [0, 3], "use": "source_x = draw * 80"},
                    {"kind": "int", "half_open": [0, 11], "use": "animation frame"},
                    {"kind": "int", "half_open": [3, 6], "use": "animation countdown baseline and current value"},
                ],
                "gem_slot_rng_draws_after_shared_reset": 30,
            },
        },
        "shared_pool_reset": {
            "function_va": "0x0059bb90-0x0059c0d3",
            "call_sites": {
                "entry_before_gem_slot_initialization": "0x005f876e",
                "completion_after_zeroing_four_weapon_count_words": "0x00601b02",
            },
            "arguments": "none",
            "seat_selection": "use dword[0x008f2040], except mode dword[0x008f20d8] == 2 forces seat 0; traverse exactly one seat table",
            "rng_free_preparation_loops": [
                {"count": 10, "stride_bytes": 40, "base_va": "0x00803640", "mutation": "dword +0 = 0"},
                {"count": 150, "stride_bytes": 100, "base_va": "0x00b04a50", "mutation": "dword +0 = 1; dword +4 = 0"},
                {"count": 100, "stride_bytes": 160, "base_va": "0x00d5e358", "mutation": "dword +0 = 0; f32 +0x40 = 0; f32 +0x44 = 0"},
                {"count": 50, "stride_bytes": 76, "base_va": "0x00847720", "mutation": "dwords +0/+0xc/+0x10 = 0; f32 +4/+8/+0x14/+0x44/+0x48 = 0"},
                {"count": 500, "stride_bytes": 84, "base_va": "0x00ac5c98", "mutation": "dword +0 = 0"},
            ],
            "conditional_record_loop": {
                "order": "i = 0 through 149",
                "record_address": "selected_seat * 0x22470 + i * 0x3a8",
                "predicate": "dword[record + 0x00849af4]",
                "skip": "predicate == 8 consumes no RNG and skips all record mutations",
                "mutation_and_rng_order_when_predicate_not_8": [
                    "dword[0x00849c64] = -1; dword[0x00849a4c] = 0; byte[0x00849de4] = 0",
                    "RngInt(0,6), convert and store f32[0x00849b40]",
                    "f32[0x00849b44] = 4; f32[0x00849b48] = 4",
                    "RngInt(0,2), store dword[0x00849b4c]",
                    "f32[0x00849a88] = 0; f32[0x00849a8c] = 0; f32[0x00849ac4] = 10",
                    "RngFloat(0.30000001192092896,2.0), divide by f64 5.0, store f32[0x00849ac8]",
                    "dword[0x00849bcc] = 500; f32[0x00849b20] = 0; dword[0x00849b18] = 1",
                    "bytes[0x00849de5] and [0x00849de6] = 0; f32[0x00849de8] = 0",
                ],
                "rng_when_predicate_not_8_in_order": [
                    {"kind": "int", "half_open": [0, 6], "store": "f32 at record + 0x00849b40"},
                    {"kind": "int", "half_open": [0, 2], "store": "dword at record + 0x00849b4c"},
                    {"kind": "float", "half_open": [0.30000001192092896, 2.0], "postprocess": "divide by f64 5.0, then round/store f32 at record + 0x00849ac8"},
                ],
                "rng_calls": "3 * count(predicate != 8)",
                "predicate_is_not_modified_by_reset": True,
            },
            "unconditional_record_loop": {
                "order": "j = 0 through 99",
                "record_base_va": "0x00af7ea4",
                "record_stride_bytes": 140,
                "mutation_before_rng": "dword +0 = 0; f32 +0x54/+0x58/+0x5c/+0x60/+0x3c = 0; dword +0x40 = 7; dwords +0x44/+0x48/+0x4c/+0x50 = 0; f32 +0x2c = f32[0x008f205c]",
                "rng": {"kind": "int", "half_open": [0, 2], "store": "convert to f32 at record + 4"},
                "rng_calls": 100,
            },
            "total_rng_calls": "3 * count(selected-seat predicates != 8) + 100",
            "completion_re_evaluates_state": "the second call rereads seat, mode, and all predicates; do not cache entry draw count",
        },
        "spawn": {
            "capacity_rule": "after active_target += growth, spawn only when active_count < floor(active_target), remaining_scalar > 0, and a free slot exists",
            "allocation": "scan slots 0 through 9 and initialize the first inactive slot",
            "at_most_one_growth_spawn_per_update": True,
            "rng_in_order": [
                {
                    "kind": "int",
                    "half_open": [0, 100],
                    "use": "source_x",
                    "branches": [
                        {"condition": "draw <= 50", "source_x": 0, "outcomes": 51},
                        {"condition": "50 < draw < 85", "source_x": 80, "outcomes": 34},
                        {"condition": "draw >= 85", "source_x": 160, "outcomes": 15},
                    ],
                },
                {"kind": "int", "half_open": [0, 11], "use": "animation frame"},
                {"kind": "int", "half_open": [1, 4], "use": "animation countdown baseline and current value"},
                {"kind": "float", "half_open": [7.0, 14.0], "use": "fall speed on the pre-scan growth spawn"},
                {"kind": "float", "half_open": [70.0, "runtime_screen_width - 150.0"], "use": "top-left x"},
            ],
            "initial_y": -60.0,
            "offscreen_respawn_difference": {
                "fall_speed_half_open": [6.0, 10.0],
                "other_rng_and_allocation": "identical; a qualifying offscreen slot is deactivated before the first free slot is scanned and respawned immediately",
            },
        },
        "update": {
            "slot_scan_order": [0, 9],
            "animation": "subtract exactly 1 from the current countdown; when current < 0, copy the baseline, increment frame, and wrap to frame 0 only when frame > 10; exact zero does not advance",
            "motion": "y += fall_speed * tick_scale",
            "offscreen_rule": "deactivate only when y > runtime_screen_height + 51 + 5; exact equality remains active",
            "remaining_step": "remaining_scalar -= tick_scale after the complete slot scan",
            "completion_rule": "complete only when remaining_scalar < 0; exact zero continues",
            "normal_difficulty_60_hz": {
                "tick_scale": 1.0,
                "active_updates_through_completion": 2681,
                "active_duration_seconds": 44.68333333333333,
                "intro_then_active_duration_seconds": 48.68333333333333,
            },
        },
        "collision": {
            "scan_order": [0, 9],
            "player_top_left_size": [40, 27],
            "gem_top_left_size": [80, 51],
            "broad_phase": "strict AABB overlap after retail float-to-int conversion",
            "narrow_phase": "diamantbig_hma versus the player's current HMA frame",
            "on_hit": "decrement active_count and deactivate the slot before audio and reward processing",
            "multiple_collections_per_scan": True,
            "score_cap": 250000000,
            "profile_write": "none; collection updates the collecting seat's live 64-bit score",
        },
        "ownership": {
            "alternating_and_solo": "after the intro, scan only the current active seat",
            "retail_duel": "each eligible tick consumes RngInt(0,2), scans that seat first, then scans its complement; the first scan owns any contested gem",
            "remake_coop": "not a retail mode; it must define a deterministic two-seat analogue without changing the retail RNG route",
        },
        "rewards": {
            "score_multiplier_applied": True,
            "ordinary_by_source_x": {"0": 50000, "80": 100000, "160": 500000},
            "super_by_source_x": {"0": 1000000, "80": 5000000, "160": 10000000},
        },
        "audio": {
            "collection_order": ["deactivate slot", "draw and play jingles", "queue bonus voice", "apply reward and create score text"],
            "jingles": {
                "asset": "jingles_sfx",
                "frequency_rng_half_open": [30000, 45000],
                "volume_index": 255,
                "pan_screen_x": "clamp(trunc_toward_zero(gem_x) + 40, 0, runtime_screen_width - 1)",
                "pan": _legacy_pan_contract(),
                "rng_consumed_per_collection": True,
            },
            "voice": {"asset": "bonus_voice", "queue_tag": 0, "padding_ms": 50, "drop_if_queue_busy": True},
        },
        "render": {
            "texture": "diamantbig",
            "hit_mask": "diamantbig_hma",
            "slot_order": [0, 9],
            "source_rect": "[source_x, animation_frame * 51, 80, 51]",
            "destination": "top-left [x, y] with retail viewport clipping",
            "rendered_during_intro": True,
        },
        "completion": {
            "condition": "remaining_scalar < 0 after its update decrement",
            "post_transition_ms": 500,
            "clears_combat_object_pools": True,
            "clears_super_flag": True,
            "next_main_state": 2,
            "originating_bonus_mode_resumed": False,
            "rng_before_state_change": "run shared_pool_reset again after zeroing four weapon-count words",
        },
        "confidence": "proven",
    }


def build_document(
    exe_path: Path = DEFAULT_EXE,
    levels_path: Path = DEFAULT_LEVELS,
) -> dict[str, Any]:
    image = PEImage(exe_path)
    if image.sha256 != EXE_SHA256:
        raise ValueError(f"unexpected executable SHA-256: {image.sha256}")
    assets = _verified_assets()
    document = {
        "version": 1,
        "schema": "warblade.bonus-modes.v1",
        "source": {
            "executable_sha256": image.sha256,
            "address_space": "32-bit PE virtual addresses",
            "verified_regions": _verified_regions(image),
            "confidence": "proven",
        },
        "assets": assets,
        "level_8_bonus": {
            "level_id": 8,
            "level_mode_id": 3,
            "authored_target_count": 20,
            "target_terminal_rule": "opcode 6 deactivates the target in non-mode-2 levels; it does not enter kamikaze state 10",
            "ordinary_enemy_projectiles_suppressed": True,
            "background_texture": "stars1",
            "counter_ownership": {
                "total_targets": "per-session player+0x918, loaded from the authored entity total",
                "actual_hits": "per-session player+0x9c0, incremented once on target death using the killing projectile owner when player+0x8b0 is set",
                "displayed_hits": "per-session player+0x9a4, reset at result entry and revealed toward actual_hits",
                "perfect_awarded": "per-session player+0x9b8 one-shot",
                "miss_counter": "none; misses are total_targets - actual_hits for each player",
                "two_player": "hit credit never transfers; each projectile-owner session has independent actual/display/perfect counters",
            },
            "rewards": {
                "authored_enemy_score": 200,
                "hit_reveal_base_score": 500,
                "hit_reveal_score_rule": "500 * player score multiplier per displayed hit",
                "reveal_countdown": {"initial": 3, "trigger": "post-decrement old value equals zero", "period_controller_updates": 4},
                "reveal_deadline_extension_ms": 1000,
                "result_deadline_extension_ms": 4000,
                "perfect_condition": "displayed_hits >= total_targets and now is strictly greater than the last reveal deadline",
                "perfect_reward_rule": "award the session's current perfect value * score multiplier exactly once",
                "perfect_reward_progression": [10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000],
                "perfect_progression_rule": "current value starts at 10,000; after a perfect, advance one clamped index for the next perfect; any actual_hits < total_targets at result expiry resets value to 10,000 and index to zero",
                "perfect_profile_counter_delta": 1,
                "two_player_perfect_selection": "scan player 0 then player 1; player 1 is the current-update candidate if both are eligible, while per-player one-shot flags allow the other candidate on a later update",
            },
            "timing_and_flow": {
                "level_complete_hold_ms": 3000,
                "result_initial_deadline_ms": 4000,
                "deadline_comparison": "strict now > deadline",
                "result_header": "B O N U S   L E V E L   R E S U L T S",
                "result_exit": "clear result deadline, bonus flag, and result-initialized flag",
                "post_result": "start the ordinary mode-13 Warp before the level transition when Warp is not already active",
                "warp_updates": 400,
                "shop_after_warp": True,
                "shop_rule": "level 8 is the second every-fourth-level shop boundary; after Warp, enter shop only when money >= 50 and the encoded fighter count is above its ship-type base, otherwise continue to level 9 Get Ready",
            },
            "confidence": "proven",
        },
        "memory_station": {
            "surface": [800, 600], "tile_size": 64, "max_grid_dimension": 8,
            "placement_iterations": 2000,
            "tile_types": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38],
            "tile_weights": [50,200,200,200,100,50,20,150,100,50,150,50,80,80,80,80,80,80,200,200,120,120,120,120,120,120,120,100,100,100,100,100,200,50,15],
            "special_roll": {"minimum_inclusive": 1, "maximum_exclusive": 1000, "type_1_when_below": 7},
            "grid_progression": {"initial_columns": 4, "initial_rows": 4, "grow_both_after_success_streak": 2, "maximum": 8, "initial_success_streak": 0},
            "timing": {"deadline_seconds": "min(trunc_toward_zero(bonus_time * 1.5), 300)", "success_hold_ms": 3000, "kill_time_input_throttle_ms": 25, "kill_time_deadline_delta_ms": -1000},
            "board_score_rng": {"multiplier_draw_half_open": [1, 11], "multiplier": 100, "effect_draws_half_open": [[0,300],[0,300],[10000,41000]]},
            "initial_point_bonus": 25000, "point_bonus_step": 25000,
            "effect_defaults": {"bonus_time_max":45,"money_cap":99990,"expanded_money_cap":999990,"money_doubler_malfunction_threshold":450000,"lives_max":5,"lives_step":1,"armour_max_fp":131072,"armour_step_fp":65536,"bullet_capacity_max":50,"speed_base_fp":262144,"speed_step_fp":45875,"speed_cap_fp":996144,"fighter_config_0_gem_progress_initial":452,"fighter_config_0_gem_progress_step":8,"memory_star_floor":20,"memory_star_cycle":3},
            "tile_effects": _tile_effects(),
            "gem_tiles": {
                "tile_types": [24,25,26,27,28,29,30],
                "shared_case_va": "0x005e4a51",
                "operation_order": [
                    "unconditionally draw and play bell1",
                    "increment shared gem progress by one configured step and test quotient modulo 100",
                    "increment shared gem progress a second time and test quotient modulo 100",
                    "if either test hits, queue gemdrop and hand off terminally to state-18 Gem Drop",
                    "otherwise continue the Memory tile-effect tail",
                ],
                "shared_progress": {
                    "storage": "per-player field player+0x8487a4",
                    "fighter_config_origin_offset": "0x1c",
                    "fighter_config_step_offset": "0x20",
                    "increments_per_match": 2,
                    "threshold_test": "logical OR of trunc_toward_zero((progress - origin) / step) % 100 == 0 after each increment",
                },
                "audio": {
                    "bell": {
                        "sfx": "bell1", "call_va": "0x005e4a51-0x005e4a87",
                        "frequency_rng_half_open": [22000,32000], "source_rate_hz": 32000,
                        "volume_index": 255, "rng_consumed_on_every_match": True,
                        "pan_screen_x": 319, "pan_at_800_width": 101.6812515258789,
                        "pan": _legacy_pan_contract(),
                    },
                    "gem_drop_voice": {
                        "asset": "gemdrop_voice", "call_va": "0x005e4b53-0x005e4b62",
                        "queue_tag": 0, "padding_ms": 50, "drop_if_queue_busy": True,
                    },
                    "ordinary_bonus_voice": "not queued by this shared case",
                },
                "threshold_transition": "uses the top-level gem_drop contract; Memory Station is abandoned and is not restored",
            },
            "completion_audio": {
                "condition": "all pairs are exhausted and dword[0x00e11478] == 0",
                "sfx": "harpgliss1_sfx",
                "call_va": "0x005e79f4-0x005e7a18",
                "frequency": "source default (-1)",
                "volume_index": 255,
                "pan": 0,
                "then_hold_ms": 3000,
                "gem_drop_threshold_bypasses_this_tail": True,
            },
            "presentation": {"atlas": "memoryblocks", "music": "memory_music", "voice": "memorystation_voice", "voice_padding_ms": 50, "countdown_voice_keys": ["one","two","three","four","five","six","seven","eight","nine","ten"], "countdown_windows": "strict n*1000 < remaining_ms < (n+1)*1000", "countdown_drop_if_voice_busy": True, "countdown_suppressed_by_kill_time": True, "face_down_source_rect": [0,0,64,64], "cursor_source_rects": [[0,320,64,64],[0,320,64,64],[64,320,64,64],[128,320,64,64],[64,320,64,64],[0,320,64,64]], "cursor_frame_period_ms": 50, "completion_sfx": "harpgliss1_sfx"},
            "confidence": "proven",
        },
        "meteor_storm": {
            "surface": [800,600], "intro_ms": 4000, "slot_count": 30, "slot_stride_bytes": 88,
            "speed": {"initial":0.0,"maximum":15.0,"acceleration_per_update":0.10000000149011612,"release_deceleration_per_update":0.18000000715255737},
            "scroll": {"initial":1.5,"growth_per_update":0.0012000000569969416},
            "spawn": {"x_half_open":[-30,800],"y_half_open":[-700,-200],"velocity_x_half_open":[-0.3,0.3],"velocity_y_half_open":[1.0,4.0],"active_target_initial":20.0,"active_target_cap":30.0,"at_most_one_per_update":True,"normal_rng_draws":6,"special_rng_draws":7,"flyby_boundary":"old_y <= -40 and new_y >= -40","flyby_frequency_hz":15000,"flyby_volume_indices":[87,21,17,23,20,23,59,14,238,255,255,211,134,81,255,69,166,255,196,255,255,176,255,32,25,74,73,71,57,223]},
            "difficulty": {"easy":{"distance":12090.0,"target_growth":0.00139999995008111,"special_threshold":7},"normal":{"distance":14000.0,"target_growth":0.00144999998155981,"special_threshold":6},"hard":{"distance":15540.0,"target_growth":0.00150000001303852,"special_threshold":5},"ace":{"distance":17000.0,"target_growth":0.00170000002253801,"special_threshold":4}},
            "distance_step": "(speed / 2 + 3) * tick_scale",
            "collision": {"player_top_left_size":[40,27],"player_source_height":27,"uses_player_hma":True,"secret_ignore_collision_rng":"RngInt(0,1000) < 992"},
            "bonus": {"weights":[50,30,10,150,80,40],"weighted_draw_half_open":[0,359],"effective_counts":[51,30,10,150,80,38],"source_x":[0,64,128,192,256,320],"source_size":[64,37],"cash":[50,100,250,0,0,0],"score":[0,0,0,1000,5000,10000]},
            "gems": {
                "texture":"diamantbig", "source_x":[0,80,160], "source_size":[80,51],
                "score":[2500,5000,10000], "gem_delta":5,
                "source_branch_va":["0x005fe763","0x005fee0b","0x005ff489"],
                "shared_progress": {
                    "storage":"per-player field player+0x8487a4",
                    "fighter_config_origin_offset":"0x1c",
                    "fighter_config_step_offset":"0x20",
                    "increments_per_pickup":5,
                    "increment_order":"add one configured step, then recompute trunc_toward_zero((progress - origin) / step), repeated exactly five times",
                    "threshold_test":"logical OR of quotient % 100 == 0 after each of the five increments",
                    "threshold_transition_ms":4000,
                    "threshold_display":"G E M   D R O P",
                    "super_drop_minimum_quotient":1000,
                    "super_drop_wrap_steps":1000,
                    "super_drop_display":"S U P E R   G E M   D R O P",
                },
                "operation_order":[
                    "award the color-specific score/profile value",
                    "perform five shared-progress increments and threshold probes",
                    "when any probe hits, queue gemdrop, display G E M   D R O P, and hand off terminally to the state-18 Gem Drop controller",
                    "when the final quotient is at least 1000, additionally subtract step * 1000 and display S U P E R   G E M   D R O P",
                    "deactivate the collected gem slot",
                    "queue the ordinary bonus voice",
                    "unconditionally draw the bell frequency and play bell1",
                ],
                "audio": {
                    "gem_drop_voice": {
                        "asset":"gemdrop_voice", "call_va":["0x005fea82-0x005fea91","0x005ff133-0x005ff142","0x005ff7b4-0x005ff7c3"],
                        "queue_tag":0, "padding_ms":50, "drop_if_queue_busy":True,
                    },
                    "ordinary_voice": {
                        "asset":"bonus_voice", "call_va":"0x005ffb14-0x005ffb23",
                        "queue_tag":0, "padding_ms":50, "drop_if_queue_busy":True,
                    },
                    "same_tick_queue_rule":"a successfully queued gemdrop voice keeps tag 0 busy, so the later ordinary bonus voice is dropped; if tag 0 was already busy, both voices are dropped",
                    "bell": {
                        "sfx":"bell1", "call_va":"0x005ffb26-0x005ffb5c",
                        "frequency_rng_half_open":[22000,32000], "source_rate_hz":32000,
                        "volume_index":255, "rng_consumed_on_every_gem_pickup":True,
                        "pan_screen_x":319, "pan_at_800_width":101.6812515258789,
                        "pan":_legacy_pan_contract(),
                    },
                },
            },
            "result": {"speed_percentage_formula":"low/high performance counters with threshold speed 30/7","tier_thresholds":{"pass":90.0,"high":99.0},"perfect":"int(speed_percentage) == 100 and accelerator was never released","normal_rewards":[{"minimum":0,"score":1000000,"cash":0},{"minimum":90,"score":2000000,"cash":1000},{"minimum":99,"score":5000000,"cash":5000},{"perfect":True,"score":10000000,"cash":25000}],"drunk_rewards":[{"minimum":0,"score":2000000,"cash":0},{"minimum":90,"score":5000000,"cash":5000},{"minimum":99,"score":10000000,"cash":10000},{"perfect":True,"score":20000000,"cash":50000}],"meteor_distance_delta":134,"transition_ms":3000},
            "presentation": {"meteor_texture":"meteors","meteor_hit_mask":"meteors_hma","bonus_texture":"meteorbonuses","bonus_hit_mask":"meteorbonuses_hma","meter_texture":"meteormeter2","music":"meteor_music","voice":"meteorstorm_voice","voice_padding_ms":50,"collision_sfx":"thumpbig","collision_frequency_hz":30000,"flyby_sfx":"meteorpass","flyby_frequency_hz":15000,"flyby_volume":"trunc(volume_index * sfx_setting / 255) / 255; at maximum setting, volume_index / 255","bonus_pickup_sfx":"bing","bonus_pickup_sfx_call_va":"0x005fe734-0x005fe755","bonus_pickup_sfx_frequency":"source default","bonus_pickup_sfx_volume_index":255,"bonus_pickup_sfx_pan":0,"gem_voice":"bonus_voice","gem_drop_voice":"gemdrop_voice","completion_music":"meteor continues through the 3000ms result hold; campaign entry resumes Warblade from its saved position"},
            "confidence": "proven",
        },
        "gem_drop": _gem_drop_contract(),
        "rank_promotion": {
            "rank_range": [1,20], "voice_pack_id": 1,
            "queue_call_va": "0x005f8fe0-0x005f9c19",
            "queue_semantics": "padding_ms is the second argument to the retail queued-voice call; all cues use default pitch and full volume",
            "common_music": "promoted", "voice_assets": _rank_voice_assets(),
            "ranks": _rank_sequences(), "confidence": "proven",
        },
    }
    mode_three_bonus = copy.deepcopy(document["level_8_bonus"])
    mode_three_bonus.pop("level_id")
    mode_three_bonus.pop("authored_target_count")
    mode_three_bonus.pop("background_texture")
    mode_three_bonus["rewards"].pop("authored_enemy_score")
    mode_three_bonus["timing_and_flow"].pop("shop_rule")
    mode_three_bonus["levels"] = mode_three_level_aliases(levels_path)
    document["mode_three_bonus"] = mode_three_bonus
    return document


def serialize(document: dict[str, Any]) -> bytes:
    return (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")


def evidence_markdown(document: dict[str, Any]) -> bytes:
    lines = [
        "# Bonus-mode contracts", "",
        "`content/bonus_modes.json` is generated from bounded regions of the pinned Warblade 1.34 executable and byte-verified original assets.", "",
        "Regenerate with `python3 tools/bonus_modes_extract.py`; verify with `python3 tools/bonus_modes_extract.py --check`.", "",
        "## Recurring mode-three levels", "",
        "The canonical `mode_three_bonus` contract binds all twelve retail mode-three levels: 8, 16, 24, 33, 41, 49, 58, 66, 74, 83, 91, and 99. Their exact target/score pairs are 20/200, 30/100, 30/200, 30/500, 40/500, 40/750, 80/500, 60/1000, 84/3000, 90/2000, 20/5000, and 80/5000. These values are slot-1 evidence aliases; per-resource LVD scores remain authoritative for kills. All twelve levels own per-session projectile-owner hit, displayed-hit, and perfect one-shot counters; reveal 500 × score multiplier per hit; share the persistent 10,000 … 10,000,000 perfect chain; and enter their recurring shop after the Warp/result route. Each mode-three shop is separate from the ordinary every-fourth-level `shop_after` cadence. `level_8_bonus` remains an explicit synchronized legacy projection.", "",
        "## Memory Station and Meteor Storm", "",
        "Both originating controllers are represented by exact RNG ranges, progression constants, reward tables, timing, collision geometry, and source-backed presentation assets. The rank-0 `memorystation` and `meteorstorm` announcements are canonical voice assets, not SFX inventory entries. Memory gem tiles play `bell1` before two progress probes; Meteor gem pickups perform five probes before their common `bonus`/`bell1` tail.", "",
        "## Gem Drop", "",
        "A progress threshold terminally abandons Memory Station or Meteor Storm, runs the pinned RNG-consuming shared pool reset, initializes ten inactive `diamantbig` slots with 30 additional draws, switches to `gems`, and enters state 18. Standard ship movement and primary-fire allocation continue through the exact 4,000-ms intro, but state 18 does not advance ordinary projectiles. The active controller grows and recycles the pool, resolves strict AABB plus HMA collisions per seat, pays ordinary or Super color rewards, and exits only after the 2,680 scalar becomes strictly negative. It never restores the originating minigame.", "",
        "## Rank promotion", "",
        f"Ranks 1–20 contain {sum(len(entry['queue']) for entry in document['rank_promotion']['ranks'])} executable-traced queued cues. The bonus modes and promotion queues use {len(document['rank_promotion']['voice_assets'])} byte-pinned voice-pack-1 files, including Memory's one-through-ten countdown. Padding values are retained per cue.", "",
        "## Pinned evidence", "",
        f"- Executable SHA-256: `{document['source']['executable_sha256']}`",
        f"- Bounded executable regions: {len(document['source']['verified_regions'])}",
        f"- Bonus presentation assets: {len(document['assets'])}", "",
        "All mode-three reward, counter, result, Warp, and shop semantics exported for the twelve campaign occurrences through level 99 are exact and closed.", "",
    ]
    return "\n".join(lines).encode("utf-8")


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate executable-backed bonus-mode contracts.")
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--levels", type=Path, default=DEFAULT_LEVELS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    try:
        document = build_document(
            arguments.exe.resolve(),
            arguments.levels.resolve(),
        )
        output = serialize(document)
        evidence = evidence_markdown(document)
        if arguments.check:
            stale = False
            for path, expected in ((arguments.output, output), (arguments.evidence, evidence)):
                if not path.is_file() or path.read_bytes() != expected:
                    print(f"stale generated bonus-mode artifact: {path}", file=sys.stderr)
                    stale = True
            return 1 if stale else 0
        _atomic_write(arguments.output.resolve(), output)
        _atomic_write(arguments.evidence.resolve(), evidence)
        print("generated recurring mode-three, Memory Station, Meteor Storm, Gem Drop, and rank 1-20 contracts")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

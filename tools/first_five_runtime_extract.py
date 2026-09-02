#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import lvd_decoder


WARBLADE_EXE_SHA256 = (
    "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
)
WARP_MALFUNCTION_VOICE_SHA256 = (
    "86a0559085e01c7b4cd818246676ee6b5efc5c3d6f7070a7ed654bb2b342deee"
)
RANK_PROMOTION_VOICE_SHA256 = {
    "congratulations": "e865e4e62ee6033c63a653898d1cea38c92c09e8adc9cd7f7e83228b0346a560",
    "lieutenant": "8be566aa2f5d9393a4780cfd4f7add9b6424d516b3e3b9d39be57000e42694c5",
    "rank": "28bed24cb3eda69aa769c36599e9744d45e8c05fafc7f5f318478ce3cc57097b",
}

EXPECTED_LEVELS = {
    1: "6938e9f31d93071b129a7c583f37751e899239bd97dd3d4c678664880d04aaf1",
    2: "0db45277db488947b998b1478523c2e8d2905c0d720ddb9a3efc489423a38934",
    3: "32f28ba7335a5fde68951f7f4af8ecf8c6f5937cb0d12e60eafb9ee229680a33",
    4: "0c816b48f007965b14a141797603a13de900879030895016e3491a56c5ab5942",
    5: "0584103d5211181bb65deef633cd6d440bbc1658bcf5ed71132e740d457044c6",
}

EXPECTED_WARP_MALFUNCTION_LEVELS = {
    1: "041be060461b6e19ba8306b2c58742635ed73f1ec2f5d000915ef706ce9448d2",
    2: "111df1346becb0295c04168364fa19288422a54bce336ad80774e9a7724864c5",
    3: "58c6cf8ecb0569f20bdd9aa5e16b5965ad33ecd683d4dff99a01f9d40fffd1f0",
    4: "359d6535204f1460b39b695d1a55653e7d90121d89a9322781dafdb83ed988d1",
}


@dataclass(frozen=True)
class Section:
    va: int
    virtual_size: int
    raw_offset: int
    raw_size: int


class PEImage:
    def __init__(self, path: Path):
        if not path.is_file():
            raise ValueError(
                f"missing retail executable: {path} "
                "(expected Game/warblade.exe inside the project root)"
            )
        self.path = path
        self.data = path.read_bytes()
        if self.data[:2] != b"MZ":
            raise ValueError(f"{path} is not a PE executable")
        pe_offset = struct.unpack_from("<I", self.data, 0x3C)[0]
        if self.data[pe_offset : pe_offset + 4] != b"PE\0\0":
            raise ValueError(f"{path} has no PE signature")
        section_count = struct.unpack_from("<H", self.data, pe_offset + 6)[0]
        optional_size = struct.unpack_from("<H", self.data, pe_offset + 20)[0]
        optional_offset = pe_offset + 24
        if struct.unpack_from("<H", self.data, optional_offset)[0] != 0x10B:
            raise ValueError(f"{path} is not a 32-bit PE image")
        self.image_base = struct.unpack_from("<I", self.data, optional_offset + 28)[0]
        section_offset = optional_offset + optional_size
        sections: list[Section] = []
        for index in range(section_count):
            offset = section_offset + index * 40
            virtual_size, rva, raw_size, raw_offset = struct.unpack_from(
                "<IIII", self.data, offset + 8
            )
            sections.append(
                Section(
                    va=self.image_base + rva,
                    virtual_size=virtual_size,
                    raw_offset=raw_offset,
                    raw_size=raw_size,
                )
            )
        self.sections = tuple(sections)

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.data).hexdigest()

    def file_offset(self, va: int, size: int = 1) -> int:
        for section in self.sections:
            extent = max(section.virtual_size, section.raw_size)
            if section.va <= va and va + size <= section.va + extent:
                offset = section.raw_offset + va - section.va
                if offset + size > section.raw_offset + section.raw_size:
                    raise ValueError(f"0x{va:08x} is uninitialized PE data")
                return offset
        raise ValueError(f"0x{va:08x} is outside mapped PE sections")

    def bytes_at(self, va: int, size: int) -> bytes:
        offset = self.file_offset(va, size)
        return self.data[offset : offset + size]

    def u32(self, va: int) -> int:
        return struct.unpack("<I", self.bytes_at(va, 4))[0]

    def f32_table(self, va: int, count: int) -> list[float]:
        return list(struct.unpack(f"<{count}f", self.bytes_at(va, count * 4)))

    def f64(self, va: int) -> float:
        return struct.unpack("<d", self.bytes_at(va, 8))[0]


# These hashes name bounded instruction/data regions rather than relying only on
# the whole-file identity. A failure therefore reports which recovered claim
# needs to be re-audited if a different executable is ever supplied.
REGION_SPECS = (
    ("rng_seed", 0x0052EA50, 112, "471a474ef40cf4ea470314ed19da93a4e9a66185d1805f17bda880039fc14c3a"),
    ("rng_core", 0x0052F750, 136, "f6af6205c8a67732c58fee3e53ebe0a4225050acc50c26db0d691e96f232ffcc"),
    ("rng_int_wrapper", 0x0052F6E0, 82, "b27d59c32a354995f57f49207261c37579988725cf7a33f6d2bf72a724f29ec0"),
    ("rng_float_wrapper", 0x0052F800, 116, "b3d93fd4ad9fe38060397b3a013a1929bc710318e445d937558bac96a4da32f2"),
    ("msvcrt_srand", 0x006FBF60, 18, "777c7c2e1401432983a0dc07393bb8ac50fdff20f61359fd9cfc41bb720419f5"),
    ("msvcrt_rand", 0x006FBF80, 56, "5f4fed02aacf359284d1e1c7714443ba059bd3e5fafcf820c424dab1359c6b47"),
    ("rng_startup_call", 0x0059F566, 31, "8209dff14dec9f1c328e6ef3b793a37946f6b89f29eff590facf1654e1ab0405"),
    ("entry_terminal_integrator", 0x006088E0, 343, "bb9bcae85b0ce88d99065edaef0441fe95ed63b4e0f0cb11af186194aabf391d"),
    ("entry_mode_1_state_2_write", 0x00608A91, 31, "8ce06c7f5af99c9832b992f7c1f58df6e2ebe74c10cda3878763453bc833d845"),
    ("entry_alternate_state_2_write", 0x00608AB5, 31, "8ce06c7f5af99c9832b992f7c1f58df6e2ebe74c10cda3878763453bc833d845"),
    ("lvd_segment_reset", 0x006145EE, 48, "1d3e772579e4d0bb303c4acf0c31d7bd0260c1c03c5eede17b3b7f81d57d427b"),
    ("platform_init", 0x0056AD01, 119, "b5484b3b589a0fe8304f153447d0d8afacb9d75f538ba7ea853337994584ffeb"),
    ("platform_update", 0x0060608C, 354, "6e1cd22e89612e12b7ae78ba21dd6a057435aa9c19bb7c0eb888d2deeeb1f245"),
    ("platform_leader_bake", 0x00609990, 332, "8216742355964209faa97c9c3a86f62dbfda565b1695fb4ca7f4142825972b38"),
    ("platform_follower_bake", 0x00609EFB, 125, "59d6a818899b9615a5e1da5e1118079551a636780e0785292011a630be69bc88"),
    ("swd_selector_2", 0x0060C16C, 1065, "9e4cf097e7ed719a573e9c5146e88eb9c574699e496c1a4c66ae93c6223457e1"),
    ("swd_selector_3", 0x0060C595, 1125, "20af1086e17c14241038cb3049811856c2d2d638eae4632ca5b3aa9b8a4f1e83"),
    ("swd_selector_fallback", 0x0060C9FA, 474, "c7c9a7129001d50b70ba39cfa3cda19ad08b923bd3db047f04bfeddc969ad11e"),
    ("state_4_consumer", 0x0060CBD4, 4128, "55251c260875d98bbdaa924b7afd5b4c7fda732b35f04da73e2682136880e3fb"),
    ("state_6_chooser", 0x0060F13A, 1982, "b559ab2af6d98ae33d2c5ca17173e7aba6949582ade8e17d4df925f91d54bc80"),
    ("state_6_aimed_fire", 0x0060E830, 1536, "1d7a0dc3b74a4b5d52d0cafefb5b6a158e72367bf35437086420297836647683"),
    ("state_6_direction_x", 0x007D0558, 160, "865a5a913eb812ee2f7e85f67c063bf0f1d64bc777ab2e1a815d04e3f888ee25"),
    ("state_6_direction_y", 0x007D05F8, 160, "eee3c6656f9db898c1eff74df95c82425bcfe2ec15f46b3e65c8a2edb6a21d03"),
    ("state_10_entry", 0x00608C8E, 44, "e4bab04cc9301430ac78b7581c7dded6f866c2fa6992354702c576063cceec58"),
    ("state_10_top_bound", 0x0060E4DE, 88, "792ff2046c922e7a0c8355e9fb51eed8759453e2a0ae2d9592e99c450343971e"),
    ("viewport_rect_init", 0x005A176E, 40, "42d3eccb4019fc6987b09e3a85e31fe3bf836f5609a5ec8513c6e51156e8aa22"),
    ("projectile_pool_scan", 0x006077D2, 50, "c6961ea74fcbefba352301bb6461b824e24a2cd47b9666e90e18ddd8b19eea69"),
    ("alien_projectile_spawn", 0x0060782C, 96, "79e2c646caa4aa72c74d425fece9c96656ddc8796ee2b74de9e98832a7878fa8"),
    ("alien_projectile_vx_zero", 0x006079E0, 17, "0f18024b30b526030baebed9c09d80988c4ae71ef3863228e898afaf097e2725"),
    ("common_projectile_update", 0x00602D49, 161, "09c1e2178cea2c00225d87255e451811ace0b79e3d96f5b5d3cb4deecc4820f8"),
    ("alien_projectile_collision", 0x0058444F, 1528, "b5d3480a8463b290916f3bdbd5ab5e6e9929dd995fe2f5ef2847b027dd163c6a"),
    ("simultaneous_pickup_dispatch", 0x00584070, 125, "c892228a4a693e9502e93f204a62f71559975442f3aee18d6e7c722841b7af35"),
    ("player_projectile_first_free_scan", 0x005DF81C, 84, "b4ee0936e3dc166ad54865761b161d6f7c2d531f61f0aa0d32a24b889e982754"),
    ("player_projectile_bounds", 0x006209BD, 335, "04a9e391434c6f2ab458da16deccc9a1920f23254d11f7958007d5d213767c50"),
    ("main_loop_projectile_order", 0x005B122D, 96, "47691243cda63b68e1537172b70ee85895aed0d9ee4a7f31813c7f00ce03a239"),
    ("late_enemy_projectile_collision_call", 0x005B1863, 8, "1d67a0958667204d4168683a1b8601c96377d334974d2a3f64f89601340d1f5c"),
    ("enemy_collision_dispatch_install", 0x0059F5FA, 10, "b49c885b78b432e810b83a520f2018e40e3d239a4f5ded74267cd71193cff85b"),
    ("scoop_tractor_geometry", 0x0058D5E5, 508, "2703b6bcb006a18a3b1aac351550cc9cf39b311c563d5b65e366908cf66a1feb"),
    ("scoop_capture_left", 0x0058D7E1, 545, "5b87b04ee5f679758c6c0614162fc2025965e73681c3c7da62ec2aa46ceb069b"),
    ("scoop_capture_right", 0x0058DA07, 545, "74ac560cf495b633173f68c8774b4ef1cf656403974057831d898ebae769b18a"),
    ("kill_counter", 0x00555C40, 512, "8f7aeb36b53225b88ec7f0e4ad0ca17af679763edf7c56179fd037cedeefe0df"),
    ("level_resolve_poll", 0x005566F0, 512, "d1ad950dade7d502aea000fbc5e9a89e8efb165648a7006fd35828dfaea0dfbd"),
    ("level_resolved_transition", 0x005568F0, 512, "4994d5ed1ab0c4c97f1d7b24c5c70b7477fd34fe26b4a7cbc33ec467f19714af"),
    ("bonus_spawn", 0x0056FF10, 1024, "cd61014630156cf61687a7198afd50562bab38eac7b45d71f98da058be692b24"),
    ("bonus_collection", 0x00571C60, 1024, "9701c01ee23a508d1f82f0510f8556dce8a67688c28d19aee301fbeb2919af10"),
    ("shop_extra_time", 0x005621B1, 128, "2337ea6196eba03e77b869e3ad0ac814acfff0b1e0806a7712cb94099fc16b13"),
    ("shop_rank_marker", 0x0056223D, 512, "3277d238bb196a5644d250737165f578bdf332b34cc8677d386a34f35c62c777"),
    ("shop_game_secret", 0x00562741, 1024, "e7b1c690c34d1f523aab219f2665449c86359d417a10d274761d1847d0dc062a"),
    ("shop_full_mask_helper", 0x00552610, 89, "e1c31b411279f81f84a338ccbc0b2504e7dcdc6bffbc630fcf2596187d970265"),
    ("shop_clear_shields_gate_award", 0x00564D19, 381, "6f99517cc659513a2431f7d5a8c99c5db4a73bce72f68a98b46985adae25ffe2"),
    ("shop_rank_promotion_entry", 0x00564F67, 1435, "55e27ee2b20be4a579f9979bae3782b82103aae06e5597fa94dcd18566d7575f"),
    ("shop_clear_shields_capped_award", 0x00565502, 258, "c26a2eb1ad9d549e5bdb16d2a87a3d5abd5e6840c56e67ff5daf54d038aa3a6d"),
    ("shop_duel_handoff_after_clear", 0x005656D5, 266, "41d0963eb0b9089116369d2d9f3adec8e6050dd2a190e9bd018cb9a6a9c3c18f"),
    ("shop_duel_handoff_normal", 0x005657E3, 263, "43aa89e8e243b32d21ac898270bc7b1545ffc3088e4ca86e3a66a68e4ad24a0d"),
    ("shop_duel_entry", 0x0061BB69, 810, "f37f8fdff98edb3669f9da6f46bdab99430510f283613dad5138d3d6a5f8815c"),
    ("shop_score_million_init", 0x00775310, 35, "55af043b675fe33d68753aaf43245f77a6d783169eacec909fb21aef26e634fd"),
    ("shop_default_rank_cap", 0x00546E30, 100, "bd25c95c038e93d4ed6a9512868d21254a53736f12ca84219adb2557ebac9f57"),
    ("shop_session_rank_zero_init", 0x00623BB3, 38, "82bf14b7a2e985fc18ba3297b10646a4f767e844234d7f7324478126eb7a6f1e"),
    ("shop_alternate_rank_zero_init", 0x005B3A98, 21, "107d87ade279c864c51ec5fd266b415cd1d337e8059bf9edcf92d35133e778cf"),
    ("rank_promotion_update", 0x005B1C8B, 1364, "09190a12de4c53215ed9b6c6fb7be41f1f10a01df05dd0febd0453477103d2db"),
    ("rank_promotion_dispatch", 0x005B012D, 31, "40ce690a4032ab5949dccb3f5a9cd3e5fa420941665c01639594433acab37354"),
    ("rank_promotion_deadline_input", 0x005ACC60, 198, "31001768bd4d9d0e2b79dbd19306a118fde56c11b2c261438608be31f1c6dab7"),
    ("rank_promotion_fire_input", 0x005EAE00, 537, "39de6a6b365a503e1a731508a2949c93f580b93ae1a0fdb651bbae2666d05e57"),
    ("rank_promotion_firework_rng", 0x005547D0, 789, "dd4bcf3d6fff700fd71e3c303b5883c340314d0084b1ef25ce280adc3d840a6d"),
    ("rank_promotion_renderer", 0x005DAE80, 4506, "60771373d8e9d0e25debd4bb8642b4babb1eac34f18c6dd34dbed29ee961da99"),
    ("rank_promotion_hud_suppression_a", 0x005EBBAB, 8, "bd880a5fff396beeb3f5667bd9c18c7fb3191937db6edd9d9e663e2db0741af5"),
    ("rank_promotion_hud_suppression_b", 0x005EC576, 8, "bd880a5fff396beeb3f5667bd9c18c7fb3191937db6edd9d9e663e2db0741af5"),
    ("rank_promotion_audio_setup", 0x005F8FE0, 3130, "f70e8fe40cdbbd176ff54b9d189cfe47eb1f342ceb074f2239a22e0ec6f78508"),
    ("rank_promotion_explo3_load", 0x005364CD, 20, "ccb1d6bc60d4515e66b5368202ea2d30687b7679451990184a9e3916e928c83b"),
    ("rank_name_table", 0x007D10A8, 782, "a680aaeb8dbdc6c79dd46c01905b371869eab8ffd8a3afbae03482ddfffe6d7c"),
    ("rank_badge_y_table", 0x007D0F98, 92, "478f0aa2e814ff946b18e79620cdc536196bc6f84c43bd935354639288a294ac"),
    ("warp_startup_interval", 0x005B2F40, 256, "abbc6875eb31e99ed0f4efe4430d25f99dcc1bdc20516259ea088626dbc50ffc"),
    ("warp_malfunction_gate", 0x00582120, 768, "c6ee2e53a34d4d5c9b9594ba7d0bf9537ced32106d525a34213071d0ac5af25e"),
    ("warp_mode_13_finalize", 0x0061B610, 2700, "7a437c3f26f672670ddf6a3e87661eaabf72e4701d4d292cd6e2d93fcf83f6c1"),
    ("warp_mode_13_stages", 0x0061C107, 766, "8b3be618d40e73c8278b49a5512b25080692942d40848f500c8809be6e6565b7"),
    ("warp_malfunction_gem", 0x00570420, 1024, "7c114cee3156bfb84adac50e9922bf5a01ad54023607ad3fadf1638b2f5f1748"),
    ("warp_mode_16_kill_a", 0x0058832B, 256, "54d0b5679321e98d4fa623c21b0a507a590e9c14ce9217db25d4b1d322093aca"),
    ("warp_mode_16_kill_b", 0x0058A2E7, 256, "0e2c8bb86aa167740201e5d9b6c65ee897c09aa8b0937ef3b4701493039ecc4b"),
    ("warp_mode_16_cue_and_dispatch", 0x005B0CFF, 516, "a332d842dc26ae43f1e112fcd81592a59bbae08c29b7e0b3e7a07540b015ae4f"),
    ("enemy_render_liveness_store", 0x0061ABC6, 53, "0459000f231f3f5e2df07d92cd26f7a2d102d8724e1ceebf7b48a7bda84f477f"),
    ("warp_malfunction_entry_sfx_load", 0x00536301, 20, "9ec7569a153d2c8d54c143e118c349aaf84c8c9d12c454964148e56acd681097"),
    ("warp_malfunction_entry_sfx_name", 0x007798A8, 13, "b72a0e64ec4f556caa6a737e7167d2504b75fe83e90a3453280ceadf7765d4f6"),
    ("warp_malfunction_entry_sfx_play", 0x0058221C, 39, "daba7e6569050b02dd8541c47e0ada1cb202e581ab83e616e7eb99df2241f8e8"),
    ("warp_malfunction_voice_load", 0x005358A3, 20, "49011f4465407d95d2f118a38e7d2a938f3113ff76cb724d1c281f710a77ee42"),
    ("warp_malfunction_voice_name", 0x007793AC, 16, "fdfeedfb9b78a0310ce3338f69dd4992ddf9bf040fd76cf155dac4333a11e7f1"),
    ("captive_weapon_fire", 0x005E0AB0, 2048, "2f80f0ea918104f8827593000f853eb031b1d4a77fc64aaa847386f856619000"),
    ("drunk_controller", 0x005EB550, 512, "42bd1faeb5eccf38e38c20d494ec8b567862fe31f167a81c54627c0194f45dd3"),
    ("player_death_cleanup", 0x00584CCE, 128, "6dfa00fac7efbfc89126910a0cd89e46b3a8f3745758ede6838fa9ef2c39763e"),
)


REL32_SPECS = (
    ("raw_rng_thunk", 0x0052856B, 0x0052F750),
    ("rng_seed_thunk", 0x005299CF, 0x0052EA50),
    ("srand_thunk", 0x005293E9, 0x006FBF60),
    ("rand_thunk", 0x00526EB9, 0x006FBF80),
    ("alien_collision_thunk", 0x00529141, 0x005842C0),
    ("player_collision_phase_thunk", 0x00525370, 0x00585840),
    ("player_projectile_update_thunk", 0x00528F16, 0x0061FFF0),
    ("common_projectile_update_thunk", 0x00525DB6, 0x00601CD0),
    ("enemy_update_thunk", 0x005289D5, 0x00605FE0),
    ("main_collision_call", 0x005B122D, 0x00525370),
    ("main_player_projectile_update_call", 0x005B1267, 0x00528F16),
    ("main_common_projectile_update_call", 0x005B1276, 0x00525DB6),
    ("main_enemy_update_call", 0x005B127B, 0x005289D5),
)


def _hex(value: int) -> str:
    return f"0x{value:08x}"


def _verify_regions(image: PEImage) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for name, va, size, expected_sha256 in REGION_SPECS:
        payload = image.bytes_at(va, size)
        actual_sha256 = hashlib.sha256(payload).hexdigest()
        if actual_sha256 != expected_sha256:
            raise ValueError(
                f"executable byte drift in {name} at {_hex(va)} ({size} bytes): "
                f"expected SHA-256 {expected_sha256}, got {actual_sha256}"
            )
        records.append(
            {
                "name": name,
                "va": _hex(va),
                "size": size,
                "sha256": actual_sha256,
            }
        )
    return records


def _rel32_target(image: PEImage, va: int) -> int:
    instruction = image.bytes_at(va, 5)
    if instruction[0] not in (0xE8, 0xE9):
        raise ValueError(
            f"expected rel32 call/jump at {_hex(va)}, got {instruction.hex()}"
        )
    displacement = struct.unpack("<i", instruction[1:])[0]
    return (va + 5 + displacement) & 0xFFFFFFFF


def _verify_rel32_edges(image: PEImage) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for name, va, expected_target in REL32_SPECS:
        actual_target = _rel32_target(image, va)
        if actual_target != expected_target:
            raise ValueError(
                f"control-flow drift in {name} at {_hex(va)}: "
                f"expected {_hex(expected_target)}, got {_hex(actual_target)}"
            )
        records.append(
            {
                "name": name,
                "instruction_va": _hex(va),
                "target_va": _hex(actual_target),
            }
        )
    return records


def _msvcrt_rand_sequence(seed: int, count: int) -> list[int]:
    state = seed & 0xFFFFFFFF
    result: list[int] = []
    for _ in range(count):
        state = (state * 214013 + 2531011) & 0xFFFFFFFF
        result.append((state >> 16) & 0x7FFF)
    return result


def _retail_rng_initial_state(seed: int) -> list[int]:
    first, second, third = _msvcrt_rand_sequence(seed, 3)
    return [
        first,
        (second * first) & 0xFFFFFFFF,
        (third * first + second * first) & 0xFFFFFFFF,
        0,
        0,
    ]


def _retail_rng_draw(state: list[int]) -> int:
    x, y, z, w, carry = state
    mixed_x = (x ^ ((x << 11) & 0xFFFFFFFF)) & 0xFFFFFFFF
    carry = (carry - mixed_x) & 0xFFFFFFFF
    x, y, z = y, z, w
    w = (w ^ (w >> 19) ^ carry ^ (carry >> 8)) & 0xFFFFFFFF
    state[:] = [x, y, z, w, carry]
    return w


def _rng_vector(seed: int, count: int = 8) -> dict[str, Any]:
    msvcrt = _msvcrt_rand_sequence(seed, 3)
    state = _retail_rng_initial_state(seed)
    initial = state.copy()
    outputs = [_retail_rng_draw(state) for _ in range(count)]
    return {
        "seed_u32": seed & 0xFFFFFFFF,
        "msvcrt_rand_outputs": msvcrt,
        "initial_words_x_y_z_w_c": initial,
        "raw_u32_outputs": outputs,
        "state_after_outputs_x_y_z_w_c": state,
    }


def _first_five_levels(levels_dir: Path) -> list[dict[str, Any]]:
    levels: list[dict[str, Any]] = []
    for level_number, expected_sha256 in EXPECTED_LEVELS.items():
        path = levels_dir / f"classic_level_{level_number:03}.lvd"
        if not path.is_file():
            raise ValueError(f"missing first-five retail LVD: {path}")
        payload = path.read_bytes()
        actual_sha256 = hashlib.sha256(payload).hexdigest()
        if actual_sha256 != expected_sha256:
            raise ValueError(
                f"retail LVD hash drift for level {level_number}: "
                f"expected {expected_sha256}, got {actual_sha256}"
            )
        document = lvd_decoder.decode_blob(payload, str(path))
        groups = document["active_groups"]
        levels.append(
            {
                "level": level_number,
                "lvd_sha256": actual_sha256,
                "level_mode_id": document["global_header"]["level_mode_id"],
                "group_mode_ids": sorted({item["group_mode_id"] for item in groups}),
                "kill_cohort_ids": sorted({item["kill_cohort_id"] for item in groups}),
                "path_opcodes": sorted(
                    {
                        point["opcode"]
                        for group in groups
                        for point in group["path_points"]
                    }
                ),
                "active_group_count": document["summary"]["active_group_count"],
                "authored_enemy_count": document["summary"]["authored_enemy_count"],
                "ordinary_state_four_score": document["unresolved_tail_array_a"][
                    "raw_words"
                ][0],
                "supplemental_spawn_records": document["global_header"][
                    "supplemental_spawn_records_raw_words"
                ],
            }
        )
    return levels


def _warp_malfunction_levels(levels_dir: Path) -> list[dict[str, Any]]:
    levels: list[dict[str, Any]] = []
    malfunction_dir = levels_dir / "warp_malfunction"
    for file_id, expected_sha256 in EXPECTED_WARP_MALFUNCTION_LEVELS.items():
        path = malfunction_dir / f"malfunction_{file_id:02}.lvd"
        if not path.is_file():
            raise ValueError(f"missing retail warp-malfunction LVD: {path}")
        payload = path.read_bytes()
        actual_sha256 = hashlib.sha256(payload).hexdigest()
        if actual_sha256 != expected_sha256:
            raise ValueError(
                f"retail malfunction LVD hash drift for file {file_id}: "
                f"expected {expected_sha256}, got {actual_sha256}"
            )
        document = lvd_decoder.decode_blob(payload, str(path))
        summary = document["summary"]
        levels.append(
            {
                "file_id": file_id,
                "lvd_sha256": actual_sha256,
                "level_mode_id": summary["level_mode_id"],
                "active_group_count": summary["active_group_count"],
                "authored_enemy_count": summary["authored_enemy_count"],
                "resource_slots": summary["nonempty_resource_slots"],
            }
        )
    return levels


def build_evidence(exe_path: Path, levels_dir: Path) -> dict[str, Any]:
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise ValueError(
            f"unexpected warblade.exe SHA-256 {image.sha256}; "
            f"expected {WARBLADE_EXE_SHA256}"
        )
    voice_path = exe_path.parent / "data" / "samples" / "voices" / "1" / "warpmalfunction.mp3"
    if not voice_path.is_file():
        raise ValueError(f"missing retail Warp-malfunction voice: {voice_path}")
    voice_sha256 = hashlib.sha256(voice_path.read_bytes()).hexdigest()
    if voice_sha256 != WARP_MALFUNCTION_VOICE_SHA256:
        raise ValueError(
            "Warp-malfunction voice hash drift: "
            f"expected {WARP_MALFUNCTION_VOICE_SHA256}, got {voice_sha256}"
        )
    rank_promotion_voices: list[dict[str, Any]] = []
    for key, expected_sha256 in RANK_PROMOTION_VOICE_SHA256.items():
        path = exe_path.parent / "data" / "samples" / "voices" / "1" / f"{key}.mp3"
        if not path.is_file():
            raise ValueError(f"missing retail rank-promotion voice: {path}")
        actual_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual_sha256 != expected_sha256:
            raise ValueError(
                f"rank-promotion voice hash drift for {key}: "
                f"expected {expected_sha256}, got {actual_sha256}"
            )
        rank_promotion_voices.append(
            {
                "key": key,
                "path": f"data/samples/voices/1/{key}.mp3",
                "sha256": actual_sha256,
                "size": path.stat().st_size,
            }
        )

    regions = _verify_regions(image)
    edges = _verify_rel32_edges(image)
    direction_x = image.f32_table(0x007D0558, 40)
    direction_y = image.f32_table(0x007D05F8, 40)

    return {
        "schema": "warblade-first-five-runtime-evidence",
        "version": 5,
        "source": {
            "exe_sha256": image.sha256,
            "address_space": "32-bit PE virtual addresses",
            "first_five_lvd_directory": "assets/original/levels",
            "warp_malfunction_voice": {
                "path": "data/samples/voices/1/warpmalfunction.mp3",
                "sha256": voice_sha256,
                "size": voice_path.stat().st_size,
            },
            "rank_promotion_voices": rank_promotion_voices,
        },
        "first_five_reachability": {
            "levels": _first_five_levels(levels_dir),
            "warp_malfunction_levels": _warp_malfunction_levels(levels_dir),
            "ordinary_entry": "Levels 1, 2, 3, and 5 use level mode 1 and terminal opcode 1, reaching state 2 without a position write.",
            "level_4": "Level 4 uses level mode 2 and terminal opcode 6, reaching state 10 at 0x00608caf.",
            "level_3_supplemental": "Level 3 supplemental record 0 is [1,1,12,1200,25] and reaches state 6.",
        },
        "enemy_motion": {
            "entry_terminal": {
                "integrator_va": "0x006088e0-0x00608a31",
                "mode_1_state_write_va": "0x00608aa5",
                "alternate_state_write_va": "0x00608ac9",
                "rule": "After the terminal opcode/threshold test, the mode-1 branch writes state 2 only; it does not assign formation X/Y. State 2 performs the later 1/20 easing.",
            },
            "entry_segment_reset": {
                "va": "0x006145ee-0x0061461d",
                "rule": "After selecting the next LVD point, retail stores float zero to segment progress before loading its acceleration.",
            },
            "formation_platform": {
                "init_va": "0x0056ad01-0x0056ad72",
                "update_va": "0x0060608c-0x006061e8",
                "leader_launch_bake_va": "0x00609990-0x00609ad5",
                "follower_launch_bake_va": "0x00609efb-0x00609f71",
                "rule": "The formation platform is mutable server-owned state. Its current X/Y drift is added to leaders and recruited followers when state 3 begins.",
            },
            "swd_return": {
                "selector_branch_vas": ["0x0060c16c", "0x0060c595", "0x0060c9fa"],
                "state_4_va": "0x0060cbd4-0x0060dbf3",
            },
            "state_6": {
                "chooser_va": "0x0060f13a-0x0060f8f7",
                "direction_x_table_va": "0x007d0558",
                "direction_y_table_va": "0x007d05f8",
                "direction_count": 40,
                "level_3_initial_heading_vectors": [
                    {
                        "heading": heading,
                        "x": direction_x[heading],
                        "y": direction_y[heading],
                    }
                    for heading in range(18, 23)
                ],
            },
            "state_10_top_bound": {
                "entry_state_write_va": "0x00608caf",
                "bound_va": "0x0060e4de-0x0060e533",
                "viewport_top_global_va": "0x00e113d8",
                "viewport_rect_init_va": "0x005a176e-0x005a1791",
                "sprite_height": image.f64(0x0077DA70),
                "rule_retail_top_left": "deactivate only when enemy_y + 32 < viewport_top - 100",
                "rule_center_coordinates": "deactivate only when center_y + 16 < viewport_top - 100",
                "strict_comparison": True,
            },
        },
        "projectiles": {
            "common_pool": {
                "capacity": 100,
                "record_stride": 140,
                "scan_va": "0x006077d2-0x006077fe",
                "active_field_base_va": "0x00af7ea4",
                "animation_phase_field_base_va": "0x00af7ea8",
                "animation_countdown_field_base_va": "0x00af7ed0",
                "slot_reuse_rule": "Ordinary type-7 spawn initializes countdown but does not overwrite phase; inactive-slot phase history survives reuse.",
            },
            "ordinary_alien_shot": {
                "spawn_va": "0x0060782c-0x00607886",
                "stored_position_is_top_left": True,
                "spawn_offset_from_enemy_top_left": [
                    image.f64(0x00779C20),
                    image.f64(0x0077D848),
                ],
                "velocity_x": 0.0,
                "velocity_x_va": "0x006079e0-0x006079eb",
                "update_va": "0x00602d49-0x00602de0",
                "bottom_bound": image.u32(0x007D32FC),
                "bottom_rule": "deactivate only when stored top-left Y is strictly greater than 600",
                "collision_va": "0x0058444f-0x00584a47",
            },
            "state_6_aimed_shot": {
                "fire_va": "0x0060e830-0x0060ee2f",
                "projectile_type": 6,
                "source_rects": [[448, 0, 32, 32], [448, 32, 32, 32]],
                "travel_range_half_open": [45.0, 55.0],
                "difficulty_multipliers": {
                    "easy": 3.0,
                    "normal": 2.2,
                    "hard": 2.0,
                    "ace": 1.8,
                },
                "target_jitter_range_half_open": [-40.0, 40.0],
                "stored_spawn_offset_from_enemy_top_left": [32.0, 25.0],
                "velocity_numerator_origin": "enemy 64x64 sprite top-left, not projectile position",
                "allocation_order": "draw travel and both target jitters before scanning slots 0 through 99",
            },
            "player_projectile_bounds": {
                "va": "0x006209bd-0x00620b0c",
                "left_and_top": -50,
                "right": image.u32(0x007D32F8) + 50,
                "comparison_input": "truncate the stored float position toward zero",
                "strictness": "-50 deactivates only below; width+50 deactivates only above",
            },
            "player_pool_and_captive_fire": {
                "capacity": 100,
                "allocator_scan_va": "0x005df81c-0x005df86f",
                "record_stride": 160,
                "allocation_order": "scan slots 0 through 99 and claim the first inactive record",
                "update_order_va": "0x0061fff0",
                "collision_order_va": "0x00585840",
                "captive_fire_va": "0x005e0ab0",
                "rule": "Main shots contribute one to the weighted weapon gate; Scoop-captive and both Mirror-side graphs contribute zero but every allocated object occupies one of the 100 physical slots. A firing cue is produced only when the allocator count is positive.",
                "hidden_selector_9": {
                    "mapped_weapon_id": 9,
                    "damage_fp": 196608,
                    "prototype_id": 67,
                    "velocity_y_fp": -1310720,
                    "size": [26, 68],
                },
            },
            "main_loop_order": [
                {"call_va": "0x005b122d", "target_va": "0x00585840", "phase": "player-projectile/enemy collision and death outcomes"},
                {"call_va": "0x005b1267", "target_va": "0x0061fff0", "phase": "existing player-projectile update"},
                {"call_va": "0x005b1276", "target_va": "0x00601cd0", "phase": "existing common/enemy-projectile update"},
                {"call_va": "0x005b127b", "target_va": "0x00605fe0", "phase": "enemy update and possible alien-shot spawn"},
                {"call_va": "0x005b1865", "dispatch_slot_va": "0x008476e8", "installed_target_va": "0x005842c0", "phase": "alien-projectile/player collision"},
            ],
        },
        "rng": {
            "seed_va": "0x0052ea50",
            "startup_seed_call_va": "0x0059f580",
            "raw_thunk_va": "0x0052856b",
            "core_va": "0x0052f750",
            "integer_wrapper_va": "0x0052f6e0",
            "float_wrapper_va": "0x0052f800",
            "state_words": [
                {"name": "x", "va": "0x00d6250c"},
                {"name": "y", "va": "0x00b0855c"},
                {"name": "z", "va": "0x00b04210"},
                {"name": "w", "va": "0x00d59f58"},
                {"name": "c", "va": "0x009efd70"},
            ],
            "initializer": {
                "msvcrt_formula": "state = state * 214013 + 2531011 (mod 2^32); return (state >> 16) & 0x7fff",
                "rule": "srand(seed), then x=rand(), y=rand()*x, z=rand()*x+y with unsigned wrap; startup-zero w and c complete the five-word state.",
            },
            "core_rule": "c -= x ^ (x << 11); rotate x=y,y=z,z=w; w = (w ^ (w >> 19)) ^ (c ^ (c >> 8)); return w, all unsigned modulo 2^32.",
            "integer_wrapper": "zero width returns 0; otherwise raw_u32 % (max-min) + min",
            "float_wrapper": "float32((max-min) * unsigned_raw_u32 * 2^-32 + min)",
            "unit_scale": image.f64(0x00778E90),
            "golden_vectors": [
                _rng_vector(0),
                _rng_vector(1),
                _rng_vector(0xFFFFFFFF),
                _rng_vector(0x12345678),
            ],
        },
        "bonuses_and_scoop": {
            "bonus_spawn_va": "0x0056ff10",
            "bonus_collection_va": "0x00571c60",
            "ordinary_scores_by_level": [50, 20, 50, 500, 50],
            "pickup_pool": {
                "capacity": 150,
                "allocation_order": "first inactive slot; collection frees a record before the later death/drop pass in the same dispatcher",
                "ordinary_order": "pickup collision/application precedes player-shot collision; pickup motion runs later",
                "duel_dispatch_va": "0x00584070-0x005840ec",
                "duel_scan_order": "one RngInt(0,2): result 0 scans [P0,P0], result 1 scans [P1,P0]",
                "alternating_scan_order": "active turn only",
            },
            "scoop": {
                "geometry_va": "0x0058d5e5-0x0058d7e0",
                "left_capture_va": "0x0058d7e1-0x0058da01",
                "right_capture_va": "0x0058da07-0x0058dc27",
                "vertical_band_pixels": 90,
                "half_width_rule": "4 + floor(clamp(player_top-enemy_top,0,90)/2)",
                "comparison": "strict endpoint-inside tests on truncated integer alien edges",
                "capacity": 2,
                "overflow_state": 5,
                "overflow_velocity_ranges_half_open": [[-4.0, 4.0], [-10.0, -6.0]],
            },
        },
        "warp_and_malfunction": {
            "startup_interval_va": "0x005b2f40-0x005b303f",
            "startup_interval_half_open": [19000, 27000],
            "startup_rng_order": "interval draw, 100 common-shot phase draws, three initializer draws for each non-state-8 alien slot, then the solo tail draw",
            "initial_progression": {"warp": 3.0, "companion": 8},
            "bonus_type_15_increment": {"warp": 0.5, "warp_cap": 8.0, "companion": 2, "companion_cap": 75},
            "level_4_increment": {"warp": 0.5, "warp_cap": 8.0, "companion": 2, "companion_cap": 60},
            "mode_13": {
                "finalize_and_skip_va": "0x0061b610-0x0061c09b",
                "stage_update_va": "0x0061c107-0x0061c404",
                "stage_updates": [100, 200, 100],
                "initial_scale": 5.0,
                "scale_step": image.f64(0x00786900),
                "velocity_step": image.f64(0x00786160),
                "velocity_divisor_float32": image.f32_table(0x0078690C, 1)[0],
                "effect_step": image.f64(0x00784128),
                "offset_step": image.f64(0x007868F0),
                "countdown_step": image.f64(0x00778E48),
                "malfunction_gate_va": "0x00582120",
                "gate_rule": "consume RngInt(0, interval), require result < 4, then require current warp scale > 120",
                "owned_skip_passes": 4,
                "owned_skip_stop_modes": [2, 3, 4],
                "player_callback": "movement, animation, death deadlines, and respawn still run; firing is disabled unless the malfunction gate changed the global mode to 16 earlier in the same frame",
                "duel_control": "session zero owns the shared Warp/malfunction fields; type-15 upgrades both Duel session progressions",
            },
            "mode_16": {
                "dispatcher_va": "0x005b0cff-0x005b0f02",
                "entry_visual_tuple": {"stage_updates": 0, "scale": 0.0, "velocity": -5.0, "effect": 0.0, "offset": 0.0},
                "resume_rule": "rearm stage 0 for 100 updates while preserving the malfunction visual tuple",
                "pickup_and_projectile_order": "pickup collision, player-shot collision, player-shot update, visual no-op, pickup motion, common shots, enemies, player callback/respawn, completion/watchdog, final enemy-shot collision",
                "malfunction_file_ids": [1, 2, 3, 4],
                "normal_first_five_resources": [
                    ["malfunction1", "malfunction4"],
                    ["malfunction3"],
                    ["malfunction4"],
                    ["alien_malfold_blue", "alien_malfold_green"],
                ],
                "enemy_spawn_draw_count": 12,
                "enemy_state": 6,
                "kill_score": 5000,
                "entry_sfx": {
                    "sample_name_va": "0x007798a8",
                    "sample_key": "alienshoot15",
                    "handle_load_va": "0x00536301-0x00536314",
                    "play_va": "0x0058221c-0x00582243",
                    "frequency_hz_half_open": [10000, 14000],
                    "source_hz": 32000,
                    "playback": "one centered cue immediately on malfunction entry",
                },
                "gem_spawn_va": "0x00570420",
                "gem_colors": ["red", "orange", "yellow", "green", "blue", "magenta"],
                "gem_rows_y": [100, 80, 60, 40, 20, 0],
                "gem_velocity_y": [1.5, 3.0, 4.0, 5.0, 6.0, 7.0],
                "gem_collection_score": 5000,
                "gem_full_mask": 63,
                "gem_full_mask_reward": "enable Super Auto Fire with a 25-ms repeat delay",
                "watchdog": {
                    "timeout_ms": 45000,
                    "comparison": "strictly greater than the last render-liveness timestamp",
                    "action": "arm the same three-second resolution deadline without killing or counting live enemies",
                    "render_refresh_va": "0x0061abc6-0x0061abfa",
                    "render_refresh_rule": "after dispatcher/watchdog, refresh for a qualifying visible enemy using strict 800x600 intersection; state 8 is excluded",
                },
                "voice_cue": {
                    "sample_name_va": "0x007793ac",
                    "sample_key": "warpmalfunction",
                    "handle_load_va": "0x005358a3-0x005358b6",
                    "initial_delay_ms": 300,
                    "comparison": "strict deadline",
                    "dormant_rearm_ms": 1600,
                    "playback": "one centered, full-volume cue at original/default pitch",
                },
            },
            "shop_after_warp": {
                "minimum_money": image.f64(0x0077B220),
                "input_guard_ms": 500,
                "logical_level_while_shopping": 4,
                "below_threshold": "bypass shop and enter level-5 Get Ready",
                "eligibility": "money >= 50 and encoded fighter count above the ship-type base (remake lives > 0)",
                "duel_selection": "test P0 eligibility first, then P1; the first eligible session becomes the sole shop participant",
                "duel_exit_sequence": "A below-cap full-mask promotion enters mode 20 first. After dismissal, promoted P0 re-tests P1 eligibility and hands over the existing shop without rearming the 500-ms guard; capped or non-promoting P0 exits can hand over immediately. P1 exit ends the shop.",
                "full_mask_exit": {
                    "helper_va": "0x00552610-0x00552669",
                    "mask": 63,
                    "action": "clear the active session mask, add 1,000,000 times score multiplier independently of the Rank Marker purchase one-shot, and promote rank when below the default cap",
                    "default_rank_cap": 20,
                    "rank_state": "current rank and highest rank start at zero; the cap is profile-derived and defaults to 20",
                    "promotion_boundary": {
                        "mode_id": 20,
                        "entry_va": "0x00564f67-0x00565501",
                        "update_va": "0x005b1c8b-0x005b21de",
                        "deadline_and_input_va": "0x005acc60-0x005acd25",
                        "held_fire_predicate_va": "0x005eae00-0x005eb018",
                        "minimum_input_lock_ms": 4000,
                        "fallback_timeout_ms": 1200000,
                        "deadline_comparison": "held fire/action may dismiss at or after the 4,000-ms deadline; the 1,200,000-ms deadline auto-dismisses at equality",
                        "per_update_rng": "consume RngInt(0,100) before deadline/input polling, including the exit update",
                        "firework_rng": {
                            "constructor_va": "0x005547d0-0x00554ae4",
                            "outer_trigger": "RngInt(0,100) < 2",
                            "primary_particle_count_half_open": [10, 50],
                            "draw_count_when_triggered": "10 + 6*N + (10 when the secondary selector is below 2)",
                            "sample_key": "explo3",
                            "sample_load_va": "0x005364cd-0x005364e0",
                            "post_constructor_selector_half_open": [30, 100],
                        },
                        "duel_p1_handoff_rng": "with all five shop voice handles loaded, consume RngInt(0,7); selector values 5 and 6 are silent",
                        "presentation": {
                            "renderer_va": "0x005dae80-0x005dc019",
                            "lines": [
                                "C O N G R A T U L A T I O N S",
                                "YOU ARE HEREBY PROMOTED TO",
                                "zero-based current rank name",
                            ],
                            "rank_badge": "64x13 ranks2.tga region; new rank 1 uses source Y 13",
                            "rank_name_table_va": "0x007d10a8",
                            "rank_names_first_23": [
                                image.bytes_at(0x007D10A8 + index * 0x22, 0x22)
                                .split(b"\0", 1)[0]
                                .decode("ascii")
                                for index in range(23)
                            ],
                            "rank_badge_y_table_va": "0x007d0f98",
                            "rank_badge_y_first_23": [0, 13, 26, 39, 52, 52, 52, 52, 52, 52, 52, 52, 52, 52, 65, 78, 91, 104, 104, 104, 104, 117, 130],
                            "prompt": "PRESS FIRE TO CONTINUE blinks every 400 ms after the input lock",
                            "music_key": "promoted",
                            "audio_setup_va": "0x005f8fe0-0x005f9c19",
                            "voice_queue": [
                                {"key": "congratulations", "padding_ms": 100},
                                {"key": "lieutenant", "padding_ms": 50},
                                {"key": "rank", "padding_ms": 50},
                            ],
                            "voice_playback": "default pitch and full 255 volume; queue arguments are inter-clip padding, not volume",
                        },
                    },
                },
            },
        },
        "level_flow_and_shop": {
            "kill_counter_va": "0x00555c40",
            "level_resolution_poll_va": "0x005566f0",
            "level_transition_va": "0x005568f0",
            "first_shop_after_level": 4,
            "first_shop_order": "full 400-update mode-13 Warp, then shop only with at least 50 money; level increments to 5 when leaving",
            "shop_cases": {
                "extra_time_va": "0x005621b1",
                "rank_marker_va": "0x0056223d",
                "game_secret_va": "0x00562741",
            },
            "extra_time_rule": "accept only below 45, then add 5 without a post-clamp",
            "rank_marker_rule": "add highest missing bit from 0x20..0x01; a later full-mask purchase pays one multiplied million once per level without clearing the mask; shop exit independently clears a full mask, pays another multiplied million, and promotes rank below the default cap of 20",
            "game_secret_rule": "select one of 30 images with the retail retry loop; grant no gameplay upgrade",
        },
        "verified_control_flow": edges,
        "verified_regions": regions,
    }


def _default_paths() -> tuple[Path, Path, Path]:
    root = Path(__file__).resolve().parents[1]
    return (
        root / "Game" / "warblade.exe",
        root / "assets" / "original" / "levels",
        root / "docs" / "evidence" / "first_five_runtime.json",
    )


def main() -> int:
    default_exe, default_levels, default_output = _default_paths()
    parser = argparse.ArgumentParser(
        description="Extract and verify executable-backed first-five runtime evidence."
    )
    parser.add_argument("--exe", type=Path, default=default_exe)
    parser.add_argument("--levels-dir", type=Path, default=default_levels)
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail unless the committed JSON is identical to freshly extracted evidence.",
    )
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    try:
        evidence = build_evidence(args.exe.resolve(), args.levels_dir.resolve())
    except (OSError, ValueError, lvd_decoder.LvdFormatError) as error:
        print(f"first-five fidelity check failed: {error}", file=sys.stderr)
        return 1

    rendered = json.dumps(evidence, indent=2, ensure_ascii=False) + "\n"
    if args.stdout:
        sys.stdout.write(rendered)
        return 0
    if args.check:
        if not args.output.is_file():
            print(f"missing generated evidence: {args.output}", file=sys.stderr)
            return 1
        if args.output.read_text(encoding="utf-8") != rendered:
            print(
                f"stale generated evidence: {args.output}; "
                "run tools/first_five_runtime_extract.py",
                file=sys.stderr,
            )
            return 1
        print(f"first-five fidelity evidence is current: {args.output}")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import sprite_atlas_extract


COMMITTED_PATH = ROOT / "content" / "sprite_frames.json"
ENEMY_ASSET_HASHES = {
    "alien001": (
        "6bd559f5fb7d03736131673fcf77a7f5925c993afb7fbfd1eeca5e2db30f760e",
        "0b04983374edaddf153dabfe571093b1106d4fb735ea3de0a2cb9db44258fa49",
    ),
    "alien_2": (
        "a805177aba06d5b725f292a0f828f24a274dd307f39b2bf2f3be9381a69b8f34",
        "41d6c093aca7c7d312ccc1a877edfca1c749d4dffdb9d211ad8a82c9ded9dbee",
    ),
    "alien_3": (
        "1995f7f478ddb3d3f53c2a46d5100223f0fd12739c709427a5ee73d4f0988308",
        "bae7ff4e43ac9b5f3e985508b502e417462b59515b4a582d5ad8dd98d2657622",
    ),
    "alien000": (
        "3dda14d46beab0e81826a02671ebcfb5d9b7cc11762c5b7ecfe9cc2b6e963575",
        "2153c68d6529e03ffa016752d8d0e12eb67f4282b7105db3fe1651a1e86d2f56",
    ),
    "alien_lilla": (
        "0876ed4f60bdc24f3368d1a1a32e86a771df9222cf354618bef313b9cf22c321",
        "f6af03a6a15fba704e14b21be11be9908e52b5adcd372aa3612731e97622bb09",
    ),
    "alien003": (
        "96194d436940fbd69b39ae768ce44ee24fe3f0c8fff874aade7b8d0f09f67815",
        "fc7d701fca04fa6f9e653bbb3295898a1a48b18aa487c19fb1595a5c27d4ba2f",
    ),
    "alien003_3": (
        "49d7e12b8d479abfbd3ec78922a620adf9adbc6a38c5f474cdb067e8ed85d1e7",
        "db057c33f556e606ae51c92877fd969afa142b0d38de6fb8c88bcd14bdd6f183",
    ),
    "alien_big1_1": (
        "56a560e9822a3ca12c7dacdd1532de02a43184e6e180c5f861e6ee7176d3629d",
        "d43422c076f19e4a8113f3b211abdb728ac329d34535e5d8fae183cc2625daab",
    ),
    "alien_big1_2": (
        "ee77517a47966e3e9a87ef8bf5576b9f7859aab84be9adc01c4eb741d924730d",
        "68193b9f640c1a24b012e8f33ecd5b981f6471720e6e56c8dcf08a170166acb6",
    ),
    "alien_big1_3": (
        "e0c40542f67210fa1a57bfbab9d590ca426476e0f4358e36bc0c2fabf4540b76",
        "d58d020f12d55367ef663c5d16c44f10e45dc405a12eb3b033765c07e3293484",
    ),
    "alien_big1_4": (
        "77e6dd5df6017c6fef91160a34efb572905638a182226166f34fb8b3e80fc109",
        "cb2e719631b6aeb5407cc6e353c551c874b1ffa3a79ad922d3772d91447e5697",
    ),
    "alien_big1_5": (
        "683673126f068c2128d2ece12f9268ae3aa930f43520f18856072cf96116d99d",
        "f9e6c0415ee0167f25ef99dddb059cae013eb39547f1b97144a8623760542ea2",
    ),
    "alien_big1_6": (
        "780c90761a50f925d3b5a21e961b56dbb5349681228de7d0bec555381feaf0c8",
        "fb54dc044be28919409b8ff7947db6b8195e33e1301365c9ba5f725ef128d3a1",
    ),
    "alien_rakett": (
        "396194d6ef26cbc866b8ae5581c2f62e754ef543093784ae95c29adb5c075dfb",
        "4a92a4d177925ffc888f69b88463a4e7b9707dbfbac96704cc1a2506e62f3c16",
    ),
    "alien_rakett_gronn": (
        "f360187200d177e614b3249c522cbb6fd68c32e44e7b67dad3a65ec18c63782b",
        "f97bc6c3487944e14c7217036dfd07f8fa74aa52b212960fcee41d961315d14e",
    ),
    "alien_baller": (
        "9c6cda05951af12f208dd989661701088275fb6ef142d49a45e197bcea8a4038",
        "e468943e3feb12fe081f4ec0e883ef0190bb11d2b31af85054b1191f77fcb682",
    ),
    "alien_baller2": (
        "ac91e8c8e07e91cc3bfd5b77171a6344bdb77b77156cd125a6f99e2ba7e88a94",
        "71451051a9ed25fa532386f54749486369261ebd760f0d72d5d1b50f0ff6eff1",
    ),
    "alien_green_lilla_t": (
        "352688c4bcbe9b3c2c390e83f3a062dc0a263b6c93376b44db41b62afb9c52e6",
        "6a6b95b5e6f8e2a6dc2b7e2412f583710b64914bd525bb35c9f86a655d087f37",
    ),
    "alien_cyan_lilla_t": (
        "42f4f0870cd332fb26f2bf8007f5c8601fa788469d3cc08abb981268d4f85f73",
        "17491459890f98a829e8038387f3dfdd5cd640b9582f8f3ecb5efb376a2413e3",
    ),
    "alien_raudkule": (
        "b53db56ae031c8e2154f0a9e4c3d9d3c3160a98506df1f70874067100c48cf65",
        "0faf940cb4a0b086460a9ad24b47c65e4129855385aeb5670183014c9c65c392",
    ),
    "alien_raudkule2": (
        "0d7ec4a55c4f08bbfd99225e3295676b289be88c7163b62737e8c228cfdc1800",
        "cf0147af950232e1145469cb2cabdc72dbb68444735b2d55e1c85a33a7c220f6",
    ),
    "alien_blavinger_gf": (
        "285135115352528a29f7a1d1f692dd91c4694840127d076499f823db082941d9",
        "e185d22d65ee4d87d0e6a860116789cb129c94f654cb0068c8f03249ccb9a105",
    ),
    "alien_blavinger_gf2": (
        "a745c3919f35db4e97e12ec9defc9c1cf277de1a307ffb7c8c9ff2c3e11933b7",
        "a3398e38ce6e1f396aca051a446c5c32d00e5ce154dbaf8c47a3d0efb1cd2d23",
    ),
    "alien_rbille": (
        "bfda091771ea721e8eaebf6fd79a862a3ea4ddf761d610c3e6b4ebcfef3b3817",
        "383c57f8011db36f08075866393edb12f6431c92de12ab997dac8e032ade6294",
    ),
    "alien_big2_1": (
        "1da17e9670abbfa2bc87a9deab2b083b2b2557e2c059a1fb5dc65310898ae0ff",
        "246f2ae2b2b98050f3e2ecb9f55be50b192fdc9ea845a07416bab7d6bc95cd7b",
    ),
    "alien_big2_2": (
        "4132e267ef0a32f339b29cdc92c6d967a5620e3580c8af329f35121eb3c1630a",
        "665e76e2e064381ba1718f5353d76267701fd0202836206e79714e09246cae28",
    ),
    "alien_big2_3": (
        "82293326f90147696c41e9753ecc2d187ecf82a562140cff5d87562092fa8c1b",
        "871ed4f97abed103725294e5800f95566d57f28f0f91701088be6cd2dd93a9b0",
    ),
    "alien_big2_4": (
        "8674358067fe3919cc9deaac886904065ce3f8c974fa8b71e3ba7effebdec569",
        "9a76057353965b5eea3fbc0de91d97c1620d11de1a0c256467e82bbdf89ae606",
    ),
    "alien_big2_5": (
        "4f9399fd8a5c64a78ad2ef87439ca0baf0af3fa8311831495a9de07f70acd850",
        "201b6696787ae1b5ac891d99879d4f1aba4a84b8c7976760473ed7e853a63e9e",
    ),
    "alien_big2_6": (
        "42a7f0814ad72d426c46ec2f1247d331763d460dd526b9a08f112fdc8b62a008",
        "aa4d4ad044cdb47b047ce8a85260bfd85dae040c26e8704fdba306d680801c74",
    ),
    "alien_gultop": (
        "36ac12d0da7b0827908f4fed3a0e161a56b087ffe7b664ffb116bb037d459373",
        "9be9a59dc422cf792bd10ec5340cd7e83b7ad017eade4fd133033a4d96b38759",
    ),
    "alien_lillatop": (
        "e8be03a599212d56636ffb520c8731b1291e12a141ab569a4ef57d58cfea15b4",
        "14399a695cea917fc993602ba5d8dbfc9647ddfa854e6aeb6ce75bc0f9ecf326",
    ),
    "alien_bluekreps": (
        "a37062a0fd23d7bd243128892862027d640722ba40483c4d35b35fa48ae04c9a",
        "fcd57a7eafcd429c0f86d6c75ed4ab79d292abf0574d9a6c9392259bec853c57",
    ),
    "alien_lbluekreps": (
        "1f07b2a9850da3d08010d6c780dd4e8cfebc22b2c6d7f8630c67dd05d7e16fc9",
        "d6d589c097fcc7a114df3883251a2b0bf72ef28fec944a372d13d43d4672bc5a",
    ),
    "alien_brownkreps": (
        "ac39f15cf8af7ad9450b7da477bf4000403c83345fc3673e46e8f942a921ae18",
        "71fe219ecb5a77a3013dc902b40175a3270e9cf4b68c8158d783f7a262359e7e",
    ),
    "alien_brownkreps2": (
        "47afd5215df0a43b8f1535cdcbd60615a18e2181596d08802ddff6354d52d10a",
        "d40cc415e55c638cf1dd3343a4a9f4d43ce45f50282054716a1a15ddbe268a4c",
    ),
    "alien_gulkreps": (
        "fe9875593cd146dc952e893e43eee11a085c9c3d8b306b13a0e3d828d6c88540",
        "ba7622bec7cf00ae8fbd33b13c7bedd09c670cbc3db47e3f0f8cb2ea69c08b80",
    ),
    "alien_rvinggk": (
        "491de8a3383b9963b4b7c4fbba1a5aecbfbd113102e0093b3fbcfd4797b83e54",
        "9fbe36466a3ea97d56e8fc0c3f9e8f5520a42a062371e6e847e6aecfd256e474",
    ),
    "alien_gvingbk": (
        "23c3af4e80e430f2d0522cdddbb7f9879c5f7904e8a67e2a400ad6e17b428345",
        "e05cdecbb41f7533624241da963741d9d0f25615c25dca1235eb75181eabc35a",
    ),
}


def _rect_tuple(value: dict[str, int]) -> tuple[int, int, int, int]:
    return value["x"], value["y"], value["width"], value["height"]


def _project_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise AssertionError(f"not a project resource path: {resource_path}")
    return ROOT / resource_path.removeprefix("res://")


class SpriteAtlasExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generated = sprite_atlas_extract.build_document()
        cls.committed_text = COMMITTED_PATH.read_text(encoding="utf-8")
        cls.committed = json.loads(cls.committed_text)

    def test_generated_document_matches_committed_artifact(self) -> None:
        expected = json.dumps(self.generated, indent=2, ensure_ascii=False) + "\n"
        self.assertEqual(expected, self.committed_text)
        self.assertEqual(11, self.generated["version"])
        self.assertEqual("warblade.sprite-frames.v11", self.generated["schema"])

    def test_source_identity_and_table_addresses_are_fixed(self) -> None:
        source = self.generated["source"]
        self.assertEqual(
            "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
            source["warblade_exe"]["sha256"],
        )
        self.assertEqual(
            {
                "projectile_source_x": "0x007cd110",
                "projectile_source_y": "0x007cd228",
                "projectile_width": "0x007cd340",
                "projectile_height": "0x007cd458",
                "projectile_next_prototype_id": "0x007cdc00",
                "projectile_persistent": "0x007cde30",
                "direction_slope_ranges": "0x007d01e0",
                "direction_mirror_indices": "0x007d0228",
                "enemy_source_y": "0x007d0268",
                "enemy_source_x": "0x007d02c0",
            },
            source["table_virtual_addresses"],
        )

    def test_hma_contract_is_binary_top_left_and_exact_size(self) -> None:
        contract = self.generated["hit_mask_format"]
        self.assertEqual(
            "(source_y + local_y) * sheet_width + source_x + local_x",
            contract["index_formula"],
        )
        for asset in contract["assets"]:
            with self.subTest(asset=asset["id"]):
                hma_path = _project_path(asset["hit_mask"])
                data = hma_path.read_bytes()
                self.assertEqual(asset["width"] * asset["height"], len(data))
                self.assertEqual({0, 1}, set(data))
                self.assertEqual(asset["occupied_pixel_count"], sum(data))
                alignment = asset["alpha_alignment"]
                self.assertGreater(
                    alignment["same_top_left_orientation_match_ppm"],
                    alignment["vertical_flip_match_ppm"],
                )
        self.assertEqual(
            list(sprite_atlas_extract.ALL_ENEMY_SHEET_IDS),
            [sheet["id"] for sheet in self.generated["enemy_sheets"]],
        )
        for sheet in self.generated["enemy_sheets"]:
            self.assertEqual((576, 96), (sheet["frame_width"], sheet["frame_height"]))

    def test_enemy_source_tables_and_rectangles_are_exact(self) -> None:
        layout = self.generated["enemy_frame_layout"]
        self.assertEqual(
            [8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7],
            layout["mirror_index_table"],
        )
        directional = layout["families"]["directional_32"]["frames"]
        self.assertEqual(
            [(index * 32, 64, 32, 32) for index in range(16)],
            [_rect_tuple(frame["source_rect"]) for frame in directional],
        )
        formation = layout["families"]["formation_animation_32"]["frames"]
        self.assertEqual(
            [
                (512, 0, 32, 32),
                (512, 32, 32, 32),
                (512, 64, 32, 32),
                (544, 0, 32, 32),
                (544, 32, 32, 32),
                (544, 64, 32, 32),
            ],
            [_rect_tuple(frame["source_rect"]) for frame in formation],
        )
        large = layout["families"]["supplemental_large_animation_64"]["frames"]
        self.assertEqual(
            [(index * 64, 0, 64, 64) for index in range(7)],
            [_rect_tuple(frame["source_rect"]) for frame in large],
        )

    def test_direction_bucket_contract_retains_float32_bits(self) -> None:
        ranges = self.generated["enemy_frame_layout"]["direction_slope_ranges"]
        self.assertEqual(
            [
                ("0xc61c4000", "0xc0a0dff8"),
                ("0xc0a0dff8", "0xbfbf9097"),
                ("0xbfbf9097", "0xbf2b0dd8"),
                ("0xbf2b0dd8", "0xbe4baf10"),
                ("0xbe4baf10", "0x3e4baf10"),
                ("0x3e4baf10", "0x3f2b0dd8"),
                ("0x3f2b0dd8", "0x3fbf9097"),
                ("0x3fbf9097", "0x40a0dff8"),
                ("0x40a0dff8", "0x461c4000"),
            ],
            [
                (
                    entry["minimum_ieee754_bits"],
                    entry["maximum_ieee754_bits"],
                )
                for entry in ranges
            ],
        )

    def test_snapshot_state_contract_selects_the_correct_frame_family(self) -> None:
        contracts = {
            entry["snapshot_match"]["authored_state"]: entry
            for entry in self.generated["renderer_state_contracts"]
        }
        self.assertEqual(1, contracts["entry"]["original_runtime_state_id"])
        self.assertEqual("directional_32", contracts["entry"]["frame_family"])
        self.assertEqual(2, contracts["formation"]["original_runtime_state_id"])
        self.assertEqual(
            "formation_animation_32", contracts["formation"]["frame_family"]
        )
        self.assertEqual(6, contracts["supplemental_large"]["original_runtime_state_id"])
        self.assertEqual(
            "supplemental_large_animation_64",
            contracts["supplemental_large"]["frame_family"],
        )
        self.assertEqual(
            [3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61,
             65, 69, 73, 78, 82, 86, 90, 94, 98],
            contracts["supplemental_large"]["level_ids"],
        )
        self.assertEqual(
            list(range(7)),
            contracts["supplemental_large"]["frame_selection"]["valid_indices"],
        )
        state_ten = contracts["state_ten"]
        self.assertEqual(10, state_ten["original_runtime_state_id"])
        self.assertEqual("formation_animation_32", state_ten["frame_family"])
        self.assertEqual("proven", state_ten["confidence"])
        self.assertEqual(
            list(range(6)), state_ten["frame_selection"]["valid_indices"]
        )
        self.assertEqual(
            "0x0060e5e9",
            state_ten["frame_selection"]["selection_instruction_region"][
                "virtual_address"
            ],
        )
        self.assertEqual(
            "0x0060e65b",
            state_ten["frame_selection"]["phase_update"]["instruction_region"][
                "virtual_address"
            ],
        )

    def test_first_one_hundred_lvd_resource_usage_and_state_reachability(self) -> None:
        usage = self.generated["level_usage"]
        self.assertEqual(list(range(1, 101)), [entry["level_id"] for entry in usage])
        self.assertEqual(
            [
                18, 22, 24, 25, 22, 20, 28, 20, 24, 30,
                32, 25, 24, 28, 32, 30, 32, 34, 28, 30,
                32, 30, 26, 30, 16, 25, 22, 24, 36, 30,
                28, 18, 30, 30, 36, 48, 36, 36, 40, 30,
                40, 60, 40, 52, 30, 90, 60, 90, 40, 14,
                76, 120, 30, 36, 60, 126, 110, 80, 40, 46, 22, 25,
            ],
            [entry["authored_enemy_count"] for entry in usage[:62]],
        )
        self.assertEqual(
            [
                "alien001", "alien001", "alien001", "alien001",
                "alien_2", "alien_2", "alien_2", "alien_2",
                "alien_3", "alien_3", "alien_3", "alien_3",
                "alien000", "alien000", "alien000", "alien000",
                "alien_lilla", "alien_lilla", "alien_lilla", "alien_lilla",
                "alien003", "alien003", "alien003", "alien003", "alien_big1_1",
                "alien_rakett", "alien_rakett", "alien_rakett", "alien_rakett",
                "alien_baller", "alien_baller", "alien_baller", "alien_baller",
                "alien_green_lilla_t", "alien_green_lilla_t",
                "alien_green_lilla_t", "alien_green_lilla_t",
                "alien_raudkule", "alien_raudkule", "alien_raudkule", "alien_raudkule",
                "alien_blavinger_gf", "alien_blavinger_gf", "alien_blavinger_gf",
                "alien_blavinger_gf2", "alien_rbille", "alien_rbille", "alien_rbille", "alien_rbille",
                "alien_big2_1",
                "alien_gultop", "alien_gultop", "alien_gultop", "alien_gultop",
                "alien_bluekreps", "alien_bluekreps", "alien_bluekreps",
                "alien_brownkreps2", "alien_rvinggk", "alien_rvinggk",
                "alien_rvinggk", "alien_gvingbk",
            ],
            [entry["enemy_sheet_id"] for entry in usage[:62]],
        )
        for entry in usage[:20]:
            self.assertEqual([1], entry["active_enemy_resource_slot_ids"])
            self.assertEqual([1], entry["group_mode_ids"])
            self.assertIn("entry", entry["snapshot_authored_states"])
        self.assertEqual([[1, 2], [1, 2], [1, 2], [1], [0, 1], [1], [1, 2], [1, 2], [1], [1, 2], [1, 2], [1, 2], [1, 2], [1, 2], [1, 2], [1, 2], [1], [1], [1, 2], [1], [1], [1], [1], [1, 2], [1], [1], [1], [1], [1], [0, 1], [1], [1], [1, 2], [1], [1, 2, 3], [1, 2, 3], [3], [1, 2], [1], [1, 2], [1], [1]], [
            entry["active_enemy_resource_slot_ids"] for entry in usage[20:62]
        ])
        self.assertEqual([4, 5, 6, 7], usage[24]["group_mode_ids"])
        self.assertEqual([4, 5, 6, 7], usage[49]["group_mode_ids"])
        self.assertEqual(
            ["alien003", "alien003_3"],
            [resource["enemy_sheet_id"] for resource in usage[22]["enemy_resources"]],
        )
        self.assertEqual(
            [50, 50, 0, 0, 0, 0],
            [resource["kill_score"] for resource in usage[24]["enemy_resources"]],
        )
        self.assertEqual(
            [f"alien_big2_{index}" for index in range(1, 7)],
            [resource["enemy_sheet_id"] for resource in usage[49]["enemy_resources"]],
        )
        self.assertEqual(
            [0, 0, 0, 0, 0, 0],
            [resource["kill_score"] for resource in usage[49]["enemy_resources"]],
        )
        self.assertEqual(
            [1, 1, 500, 1377, 8],
            usage[49]["supplemental_spawn_records"][0]["raw_words"],
        )
        self.assertEqual(["entry", "formation"], usage[49]["snapshot_authored_states"])
        self.assertEqual(
            ["entry", "kamikaze"], usage[3]["snapshot_authored_states"]
        )
        self.assertEqual(["entry"], usage[7]["snapshot_authored_states"])
        self.assertEqual(
            [3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61,
             65, 69, 73, 78, 82, 86, 90, 94, 98],
            [
                entry["level_id"]
                for entry in usage
                if "supplemental_large" in entry["snapshot_authored_states"]
            ],
        )
        self.assertEqual(["entry"], usage[15]["snapshot_authored_states"])
        self.assertEqual(
            ["entry", "kamikaze"], usage[19]["snapshot_authored_states"]
        )

    def test_enemy_projectile_sheet_masks_cover_both_types_and_all_sheets(self) -> None:
        contracts = self.generated["enemy_projectile_contracts"]
        expected = {
            "ordinary_type_7": {
                "alien001": [([0, 0, 5, 13], 76), ([0, 0, 5, 13], 76)],
                "alien_2": [([0, 0, 3, 11], 38), ([0, 0, 3, 11], 38)],
                "alien_3": [([0, 0, 5, 12], 71), ([0, 0, 6, 12], 73)],
                "alien000": [([0, 0, 7, 13], 104), ([0, 0, 7, 13], 96)],
                "alien_lilla": [([0, 0, 5, 9], 43), ([0, 0, 5, 9], 42)],
                "alien003": [([0, 0, 6, 12], 66), ([0, 0, 5, 12], 49)],
                "alien003_3": [([0, 0, 5, 11], 64), ([0, 0, 5, 12], 49)],
                "alien_big1_1": [([0, 0, 29, 31], 911), ([0, 0, 29, 21], 466)],
                "alien_big1_2": [([0, 0, 29, 31], 918), ([0, 0, 29, 21], 466)],
                "alien_big1_3": [([0, 0, 29, 31], 916), ([0, 0, 29, 21], 481)],
                "alien_big1_4": [([0, 0, 29, 31], 925), ([0, 0, 29, 21], 488)],
                "alien_big1_5": [([0, 0, 29, 31], 916), ([0, 0, 29, 21], 487)],
                "alien_big1_6": [([0, 0, 29, 31], 924), ([0, 0, 29, 21], 487)],
                "alien_rakett": [([0, 0, 5, 11], 64), ([0, 3, 5, 11], 46)],
                "alien_rakett_gronn": [([0, 0, 5, 11], 64), ([0, 3, 5, 11], 42)],
                "alien_baller": [([0, 0, 7, 7], 64), ([0, 0, 9, 9], 84)],
                "alien_baller2": [([2, 2, 3, 3], 4), ([2, 2, 3, 3], 4)],
                "alien_green_lilla_t": [([0, 0, 5, 5], 36), ([0, 0, 6, 6], 38)],
                "alien_cyan_lilla_t": [([0, 0, 5, 5], 36), ([0, 0, 5, 5], 36)],
                "alien_raudkule": [([2, 2, 5, 7], 24), ([2, 2, 4, 5], 10)],
                "alien_raudkule2": [([0, 0, 7, 9], 64), ([0, 0, 7, 9], 64)],
                "alien_blavinger_gf": [([2, 2, 7, 7], 20), ([0, 0, 9, 9], 47)],
                "alien_blavinger_gf2": [([2, 2, 7, 7], 20), ([0, 0, 9, 9], 52)],
                "alien_rbille": [([0, 0, 7, 7], 49), ([0, 0, 7, 7], 50)],
                "alien_big2_1": [([0, 0, 28, 31], 857), ([0, 0, 28, 13], 172)],
                "alien_big2_2": [([0, 0, 28, 31], 855), ([0, 0, 28, 13], 169)],
                "alien_big2_3": [([0, 0, 28, 31], 847), ([0, 0, 28, 13], 166)],
                "alien_big2_4": [([0, 0, 28, 31], 836), ([0, 0, 28, 13], 164)],
                "alien_big2_5": [([0, 0, 28, 31], 849), ([0, 0, 28, 13], 167)],
                "alien_big2_6": [([0, 0, 29, 31], 911), ([0, 0, 28, 13], 203)],
                "alien_gultop": [([0, 0, 9, 11], 78), ([0, 0, 9, 11], 78)],
                "alien_lillatop": [([0, 0, 7, 9], 52), ([2, 0, 9, 9], 52)],
                "alien_bluekreps": [([0, 0, 11, 11], 82), ([2, 2, 9, 9], 44)],
                "alien_lbluekreps": [([0, 0, 11, 11], 80), ([0, 0, 11, 11], 80)],
                "alien_brownkreps": [([0, 0, 11, 11], 64), ([0, 0, 11, 11], 80)],
                "alien_brownkreps2": [([0, 0, 11, 11], 81), ([0, 0, 11, 11], 80)],
                "alien_gulkreps": [([0, 0, 11, 11], 80), ([3, 3, 8, 8], 32)],
                "alien_rvinggk": [([0, 0, 13, 13], 119), ([0, 0, 13, 13], 120)],
                "alien_gvingbk": [([0, 0, 13, 13], 100), ([0, 0, 13, 13], 100)],
            },
            "supplemental_state_6_type_6": {
                "alien001": [([0, 1, 11, 12], 72), ([0, 0, 11, 11], 132)],
                "alien_2": [([2, 2, 9, 9], 64), ([0, 0, 11, 11], 144)],
                "alien_3": [([0, 0, 31, 12], 94), ([0, 0, 31, 12], 135)],
                "alien000": [([0, 0, 13, 16], 187), ([0, 0, 13, 16], 186)],
                "alien_lilla": [([0, 0, 11, 11], 69), ([0, 0, 11, 11], 98)],
                "alien003": [([2, 2, 9, 9], 64), ([0, 0, 11, 11], 128)],
                "alien003_3": [([2, 2, 9, 9], 64), ([0, 0, 11, 11], 128)],
                "alien_big1_1": [([0, 0, 31, 31], 879), ([0, 0, 31, 15], 152)],
                "alien_big1_2": [([0, 0, 31, 31], 878), ([0, 0, 31, 16], 144)],
                "alien_big1_3": [([0, 0, 31, 31], 900), ([0, 0, 31, 17], 162)],
                "alien_big1_4": [([0, 0, 31, 31], 897), ([0, 0, 31, 17], 165)],
                "alien_big1_5": [([0, 0, 31, 31], 898), ([0, 0, 31, 17], 172)],
                "alien_big1_6": [([0, 0, 31, 31], 900), ([0, 0, 31, 17], 172)],
                "alien_rakett": [([5, 5, 12, 12], 40), ([0, 2, 17, 19], 192)],
                "alien_rakett_gronn": [([6, 6, 11, 11], 20), ([0, 2, 17, 19], 196)],
                "alien_baller": [([0, 0, 13, 13], 68), ([0, 0, 13, 13], 116)],
                "alien_baller2": [([6, 6, 7, 7], 4), ([6, 6, 7, 7], 4)],
                "alien_green_lilla_t": [([0, 0, 12, 11], 145), ([2, 2, 31, 10], 19)],
                "alien_cyan_lilla_t": [([0, 0, 11, 11], 144), ([4, 4, 7, 8], 17)],
                "alien_raudkule": [([4, 4, 9, 9], 18), ([0, 0, 17, 17], 276)],
                "alien_raudkule2": [([0, 0, 17, 17], 276), (None, 0)],
                "alien_blavinger_gf": [([0, 0, 13, 13], 132), ([0, 0, 13, 13], 116)],
                "alien_blavinger_gf2": [([0, 0, 13, 13], 56), ([0, 0, 13, 13], 40)],
                "alien_rbille": [([0, 0, 17, 17], 308), ([0, 0, 17, 17], 309)],
                "alien_big2_1": [([0, 0, 31, 31], 1024), ([0, 0, 31, 14], 388)],
                "alien_big2_2": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 374)],
                "alien_big2_3": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 362)],
                "alien_big2_4": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 336)],
                "alien_big2_5": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 361)],
                "alien_big2_6": [([0, 0, 31, 31], 1024), ([0, 0, 31, 14], 407)],
                "alien_gultop": [([0, 2, 9, 11], 88), ([0, 2, 9, 11], 88)],
                "alien_lillatop": [([0, 4, 9, 11], 72), ([0, 4, 9, 11], 72)],
                "alien_bluekreps": [([0, 0, 11, 11], 128), ([2, 2, 9, 9], 48)],
                "alien_lbluekreps": [([0, 0, 11, 11], 128), ([0, 0, 11, 11], 128)],
                "alien_brownkreps": [([0, 0, 11, 11], 122), ([0, 0, 11, 11], 128)],
                "alien_brownkreps2": [([0, 0, 11, 11], 128), ([0, 0, 11, 11], 128)],
                "alien_gulkreps": [([0, 0, 11, 11], 128), ([3, 3, 8, 8], 32)],
                "alien_rvinggk": [([0, 0, 17, 17], 74), ([0, 0, 17, 17], 267)],
                "alien_gvingbk": [([0, 0, 17, 17], 276), ([2, 2, 17, 17], 208)],
            },
        }
        self.assertEqual("alienshoot10", contracts["ordinary_type_7"]["sound_key"])
        self.assertEqual([3], contracts["ordinary_type_7"]["suppressed_level_modes"])
        self.assertEqual(
            "alienshoot2", contracts["supplemental_state_6_type_6"]["sound_key"]
        )
        self.assertEqual(
            [3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61,
             65, 69, 73, 78, 82, 86, 90, 94, 98],
            contracts["supplemental_state_6_type_6"]["reachable_levels"],
        )
        for contract_id, sheets in expected.items():
            evidence = contracts[contract_id]["retail_broad_phase_evidence"]
            self.assertEqual(
                "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
                evidence["retail_executable_sha256"],
            )
            self.assertEqual("0x00555a04-0x00555a94", evidence["hma_metadata_capture_va"])
            self.assertEqual(8, evidence["captured_metadata_int_count_per_resource_slot"])
            self.assertEqual("0x00803bd0", evidence["resource_slot_metadata_table_base_va"])
            self.assertEqual(
                ["0x0056bed6", "0x0056d720"],
                evidence["entity_initialization_copy_vas"],
            )
            self.assertEqual("0x00584459-0x005844e2", evidence["collision_consumer_va"])
            self.assertEqual(
                list(sprite_atlas_extract.ALL_ENEMY_SHEET_IDS),
                list(contracts[contract_id]["sheet_masks"]),
            )
            for sheet_id, expected_phases in sheets.items():
                sheet = contracts[contract_id]["sheet_masks"][sheet_id]
                phases = sheet["phases"]
                self.assertEqual(expected_phases[0][0], sheet["retail_broad_phase_bounds"])
                self.assertEqual(ENEMY_ASSET_HASHES[sheet_id][0], sheet["texture_sha256"])
                self.assertEqual(ENEMY_ASSET_HASHES[sheet_id][1], sheet["hit_mask_sha256"])
                self.assertEqual([0, 1], [phase["phase"] for phase in phases])
                self.assertEqual(
                    expected_phases,
                    [
                        (
                            phase["local_inclusive_bounds"],
                            phase["occupied_pixel_count"],
                        )
                        for phase in phases
                    ],
                )
        self.assertEqual(
            "0x0060788c-0x0060792e",
            contracts["ordinary_type_7"]["retail_broad_phase_evidence"]["projectile_spawn_copy_va"],
        )
        self.assertEqual(
            ["0x3fc", "0x400", "0x404", "0x408"],
            contracts["ordinary_type_7"]["retail_broad_phase_evidence"]["projectile_entity_offsets"],
        )
        self.assertEqual(
            "0x0060f016-0x0060f0b8",
            contracts["supplemental_state_6_type_6"]["retail_broad_phase_evidence"]["projectile_spawn_copy_va"],
        )
        self.assertEqual(
            ["0x3ec", "0x3f0", "0x3f4", "0x3f8"],
            contracts["supplemental_state_6_type_6"]["retail_broad_phase_evidence"]["projectile_entity_offsets"],
        )

    def test_pinned_empty_projectile_phases_require_explicit_allowance(self) -> None:
        hma_path = (
            ROOT
            / "assets"
            / "original"
            / "textures"
            / "enemies"
            / "alien_raudkule2.hma"
        )
        phase_rect = {"x": 448, "y": 32, "width": 32, "height": 32}
        with self.assertRaises(sprite_atlas_extract.SpriteAtlasError):
            sprite_atlas_extract._occupied_bounds(hma_path, 576, phase_rect)
        self.assertEqual(
            {"local_inclusive_bounds": None, "occupied_pixel_count": 0},
            sprite_atlas_extract._occupied_bounds(
                hma_path,
                576,
                phase_rect,
                allow_empty=True,
            ),
        )
        mkuler_path = hma_path.with_name("alien_mkuler.hma")
        ordinary_contract = self.generated["enemy_projectile_contracts"][
            "ordinary_type_7"
        ]["sheet_masks"]["alien_mkuler"]
        self.assertIsNone(ordinary_contract["retail_broad_phase_bounds"])
        for source_y, phase in zip((0, 32), ordinary_contract["phases"], strict=True):
            rect = {"x": 480, "y": source_y, "width": 32, "height": 32}
            with self.assertRaises(sprite_atlas_extract.SpriteAtlasError):
                sprite_atlas_extract._occupied_bounds(mkuler_path, 576, rect)
            self.assertEqual(
                {"local_inclusive_bounds": None, "occupied_pixel_count": 0},
                sprite_atlas_extract._occupied_bounds(
                    mkuler_path, 576, rect, allow_empty=True
                ),
            )
            self.assertIsNone(phase["local_inclusive_bounds"])
            self.assertEqual(0, phase["occupied_pixel_count"])

    def test_supplemental_records_link_each_sheet_to_state_six(self) -> None:
        linkages = self.generated["supplemental_spawn_linkages"]
        self.assertEqual(
            [3, 7, 11, 15, 19, 23, 28, 32, 36, 36, 40, 44, 48, 53, 53, 57, 61,
             65, 65, 69, 73, 78, 82, 86, 90, 94, 98],
            [entry["level_id"] for entry in linkages],
        )
        self.assertEqual(
            [
                record["raw_words"]
                for records in sprite_atlas_extract.EXPECTED_SUPPLEMENTAL_RECORDS.values()
                for record in records
            ],
            [entry["raw_words"] for entry in linkages],
        )
        self.assertEqual(
            [
                "alien001",
                "alien_2",
                "alien_3",
                "alien000",
                "alien_lilla",
                "alien003",
                "alien_rakett",
                "alien_baller",
                "alien_cyan_lilla_t",
                "alien_green_lilla_t",
                "alien_raudkule",
                "alien_blavinger_gf2",
                "alien_rbille",
                "alien_gultop",
                "alien_gultop",
                "alien_brownkreps",
                "alien_rvinggk",
                "alien_lblaa_royr",
                "alien_lila_royr",
                "alien_lblaa_makk",
                "alien_rocktalien",
                "alien_rspis",
                "alien001_gul",
                "alien_lysper2",
                "alien_n1_gron",
                "alien_n2_green",
                "alien_mkuler",
            ],
            [entry["resource_selector_result"]["enemy_sheet_id"] for entry in linkages],
        )
        for linkage in linkages:
            self.assertEqual(linkage["raw_words"][0], linkage["spawn_count"])
            self.assertEqual(linkage["raw_words"][1], linkage["resource_selector"])
            self.assertEqual(6, linkage["original_runtime_state_id"])
            self.assertEqual("supplemental_large", linkage["snapshot_authored_state"])
            self.assertEqual("supported", linkage["confidence"])
        level_28 = next(
            entry for entry in linkages
            if entry["level_id"] == 28 and entry["record_index"] == 0
        )
        self.assertEqual([4, 0, 0, 0], level_28["fixed_record_raw_words"])
        self.assertEqual(4, level_28["animation_phase_count"])
        self.assertEqual([0, 1, 2, 3], level_28["valid_animation_phases"])
        level_32 = next(
            entry for entry in linkages
            if entry["level_id"] == 32 and entry["record_index"] == 0
        )
        self.assertEqual([4, 0, 0, 0], level_32["fixed_record_raw_words"])
        self.assertEqual(4, level_32["animation_phase_count"])
        self.assertEqual([0, 1, 2, 3], level_32["valid_animation_phases"])
        level_36 = [entry for entry in linkages if entry["level_id"] == 36]
        self.assertEqual([0, 1], [entry["record_index"] for entry in level_36])
        self.assertEqual([2, 1], [entry["resource_selector"] for entry in level_36])
        self.assertTrue(all(entry["animation_phase_count"] == 4 for entry in level_36))
        level_53 = [entry for entry in linkages if entry["level_id"] == 53]
        self.assertEqual([0, 1], [entry["record_index"] for entry in level_53])
        self.assertEqual([1, 1], [entry["resource_selector"] for entry in level_53])
        self.assertTrue(all(entry["animation_phase_count"] == 4 for entry in level_53))
        level_57 = next(entry for entry in linkages if entry["level_id"] == 57)
        self.assertEqual(3, level_57["resource_selector"])
        self.assertEqual("alien_brownkreps", level_57["resource_selector_result"]["enemy_sheet_id"])
        self.assertEqual(4, level_57["animation_phase_count"])
        level_61 = next(entry for entry in linkages if entry["level_id"] == 61)
        self.assertEqual(1, level_61["resource_selector"])
        self.assertEqual("alien_rvinggk", level_61["resource_selector_result"]["enemy_sheet_id"])
        self.assertEqual(4, level_61["animation_phase_count"])

    def test_fighter_frames_and_banking_producer_are_exact(self) -> None:
        for sheet in self.generated["fighter_sheets"]:
            with self.subTest(sheet=sheet["id"]):
                self.assertEqual(
                    [(index * 40, 0, 40, 27) for index in range(11)],
                    [_rect_tuple(frame["source_rect"]) for frame in sheet["frames"]],
                )
                self.assertEqual([27], sheet["blank_storage_rows"])
                hma = _project_path(sheet["hit_mask"]).read_bytes()
                self.assertEqual(bytes(440), hma[27 * 440 : 28 * 440])
                producer = sheet["producer_rule"]
                self.assertEqual("5.0", producer["initial_frame_value"])
                self.assertEqual("0.5", producer["step_per_update"])
                self.assertEqual(
                    "frame_value = max(0.0, frame_value - 0.5)",
                    producer["left_active"],
                )
                self.assertEqual(
                    (
                        "frame_value += 0.5; when frame_value reaches 11.0, "
                        "reset it to 10.0"
                    ),
                    producer["right_active"],
                )
                self.assertEqual("10.5", producer["maximum_transient_frame_value"])
                self.assertEqual(10, producer["maximum_rendered_frame_index"])
                self.assertEqual("sprite_frame", producer["snapshot_field"])

    def test_playable_projectile_rectangles_and_aliases_are_exact(self) -> None:
        expected = {
            0: (32, 0, 4, 10),
            1: (48, 0, 4, 10),
            2: (32, 15, 4, 10),
            3: (48, 15, 4, 10),
            4: (80, 0, 6, 10),
            5: (80, 15, 6, 10),
            6: (32, 31, 10, 12),
            7: (64, 31, 10, 12),
            8: (48, 31, 8, 12),
            9: (112, 0, 4, 10),
            10: (48, 46, 8, 12),
            11: (112, 15, 4, 10),
            12: (32, 46, 9, 11),
            13: (64, 46, 9, 12),
            14: (96, 0, 8, 10),
            15: (128, 0, 8, 10),
            16: (96, 15, 8, 10),
            17: (128, 15, 8, 10),
            18: (176, 0, 22, 41),
            19: (0, 0, 32, 78),
            20: (144, 0, 32, 78),
            21: (144, 0, 32, 78),
            22: (240, 0, 16, 100),
            23: (256, 0, 16, 100),
            24: (272, 0, 16, 100),
            25: (304, 0, 21, 50),
            26: (336, 0, 21, 51),
            27: (368, 0, 21, 50),
            28: (400, 0, 22, 52),
            29: (432, 0, 22, 52),
            30: (304, 52, 11, 25),
            31: (320, 52, 11, 25),
            32: (336, 52, 11, 25),
            33: (352, 52, 11, 25),
            34: (368, 52, 11, 25),
            35: (176, 46, 8, 50),
            36: (192, 46, 8, 50),
            37: (208, 46, 8, 50),
            38: (80, 46, 11, 20),
            39: (112, 46, 16, 39),
            40: (128, 46, 16, 39),
            41: (128, 46, 16, 39),
            42: (48, 76, 4, 6),
            43: (32, 76, 5, 6),
            44: (64, 76, 5, 6),
            45: (96, 31, 4, 5),
            46: (128, 31, 4, 5),
            47: (48, 61, 12, 5),
            48: (32, 61, 2, 5),
            49: (208, 0, 22, 41),
            50: (288, 0, 16, 100),
            55: (32, 68, 2, 5),
            56: (48, 68, 12, 5),
            57: (224, 46, 8, 50),
            58: (304, 52, 11, 25),
            59: (320, 52, 11, 25),
            60: (336, 52, 11, 25),
            61: (352, 52, 11, 25),
            62: (368, 52, 11, 25),
            63: (80, 0, 6, 10),
            64: (80, 0, 6, 10),
            65: (80, 0, 6, 10),
            66: (48, 0, 4, 10),
        }
        sheet = self.generated["projectile_sheet"]
        actual = {
            frame["prototype_id"]: _rect_tuple(frame["source_rect"])
            for frame in sheet["frames"]
        }
        self.assertEqual(expected, actual)
        for prototype_id in (22, 23, 24, 35, 36, 37, 50, 57):
            self.assertEqual(
                [7],
                next(
                    frame["weapon_ids"]
                    for frame in sheet["frames"]
                    if frame["prototype_id"] == prototype_id
                ),
            )
        self.assertEqual(
            [
                [1, 66],
                [4, 63, 64, 65],
                [20, 21],
                [30, 58],
                [31, 59],
                [32, 60],
                [33, 61],
                [34, 62],
                [40, 41],
            ],
            sheet["exact_alias_groups"],
        )
        persistent = {
            frame["prototype_id"]
            for frame in sheet["frames"]
            if frame["persistent"]
        }
        self.assertEqual({22, 23, 24, 35, 36, 37, 50, 57}, persistent)

    def test_every_exported_rectangle_is_in_bounds_and_reuses_mask_coordinates(
        self,
    ) -> None:
        enemy_families = self.generated["enemy_frame_layout"]["families"].values()
        for family in enemy_families:
            for frame in family["frames"]:
                rect = frame["source_rect"]
                self.assertEqual(rect, frame["hit_mask_rect"])
                self.assertGreater(rect["width"], 0)
                self.assertGreater(rect["height"], 0)
                self.assertLessEqual(rect["x"] + rect["width"], 576)
                self.assertLessEqual(rect["y"] + rect["height"], 96)
        for sheet in self.generated["fighter_sheets"]:
            for frame in sheet["frames"]:
                rect = frame["source_rect"]
                self.assertEqual(rect, frame["hit_mask_rect"])
                self.assertLessEqual(rect["x"] + rect["width"], sheet["sheet_width"])
                self.assertLessEqual(
                    rect["y"] + rect["height"], sheet["sheet_storage_height"]
                )
        projectile_sheet = self.generated["projectile_sheet"]
        for frame in projectile_sheet["frames"]:
            rect = frame["source_rect"]
            self.assertEqual(rect, frame["hit_mask_rect"])
            self.assertLessEqual(
                rect["x"] + rect["width"], projectile_sheet["sheet_width"]
            )
            self.assertLessEqual(
                rect["y"] + rect["height"], projectile_sheet["sheet_height"]
            )

    def test_evidence_inventory_describes_the_current_full_catalog(self) -> None:
        evidence = (ROOT / "docs" / "evidence" / "SPRITE_ATLAS.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("all 100 campaign-level sprite rectangles", evidence)
        self.assertIn("declares 80 ordered enemy sheets", evidence)
        self.assertIn("twenty-seven nonzero supplemental records", evidence)
        self.assertIn("all 80 current sheets", evidence)
        self.assertNotIn("first-sixty-two sprite rectangles", evidence)


if __name__ == "__main__":
    unittest.main(verbosity=2)

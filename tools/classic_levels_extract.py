#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

import lvd_decoder
from first_five_runtime_extract import PEImage, WARBLADE_EXE_SHA256


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = ROOT / "Game" / "warblade.exe"
DEFAULT_LEVELS_DIR = ROOT / "assets" / "original" / "levels"
DEFAULT_ENEMY_DIR = ROOT / "assets" / "original" / "textures" / "enemies"
DEFAULT_FACTS = ROOT / "tools" / "known_facts.json"
DEFAULT_LEVEL_CONTENT = ROOT / "content" / "levels.json"
DEFAULT_DECODED_DIR = ROOT / "content" / "lvd_decoded"
DEFAULT_EVIDENCE = ROOT / "docs" / "evidence" / "classic_levels.json"
DEFAULT_MARKDOWN = ROOT / "docs" / "evidence" / "LVD_CLASSIC_LEVELS.md"
DEFAULT_PROVENANCE = ROOT / "docs" / "evidence" / "provenance_manifest.json"

EXPECTED_LEVEL_IDS = tuple(range(1, 101))
EXPECTED_SHOP_LEVEL_IDS = tuple(range(4, 101, 4))
EXPECTED_SUPPLEMENTAL_LEVEL_IDS = (
    3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61,
    65, 69, 73, 78, 82, 86, 90, 94, 98,
)
EXPECTED_MODE_THREE_LEVEL_IDS = (8, 16, 24, 33, 41, 49, 58, 66, 74, 83, 91, 99)
EXPECTED_LEVEL_MODES_51_100 = {
    **{level_id: 1 for level_id in (51, 52, 53, 55, 56, 57, 59, 60, 61)},
    **{level_id: 2 for level_id in (54, 62, 70, 79, 87, 95)},
    **{level_id: 3 for level_id in (58, 66, 74, 83, 91, 99)},
    **{level_id: 4 for level_id in (75, 100)},
    **{
        level_id: 6
        for level_id in (
            63, 64, 65, 67, 68, 69, 71, 72, 73, 76, 77, 88, 89, 90, 92, 93,
        )
    },
    **{level_id: 1 for level_id in (78, 80, 81, 82, 84, 85, 86, 94, 96, 97, 98)},
}
EXPECTED_ENEMY_SHEET_IDS = (
    "alien001", "alien_2", "alien_3", "alien000", "alien_lilla", "alien003",
    "alien003_3", "alien_big1_1", "alien_big1_2", "alien_big1_3",
    "alien_big1_4", "alien_big1_5", "alien_big1_6", "alien_rakett",
    "alien_rakett_gronn", "alien_baller", "alien_baller2", "alien_green_lilla_t",
    "alien_cyan_lilla_t", "alien_raudkule", "alien_raudkule2",
    "alien_blavinger_gf", "alien_blavinger_gf2", "alien_rbille", "alien_big2_1",
    "alien_big2_2", "alien_big2_3", "alien_big2_4", "alien_big2_5",
    "alien_big2_6", "alien_gultop", "alien_lillatop", "alien_bluekreps",
    "alien_lbluekreps", "alien_brownkreps", "alien_brownkreps2",
    "alien_gulkreps", "alien_rvinggk", "alien_gvingbk", "alien_lila_royr",
    "alien_lblaa_royr", "alien_lilla_makk", "alien_lblaa_makk",
    "alien_rocktalien", "alien_rocktalieng", "alien_big3_1", "alien_big3_2",
    "alien_big3_3", "alien_big3_4", "alien_big3_5", "alien_big3_6",
    "alien_gspis", "alien_rspis", "alien001_gul", "alien001_raud",
    "alien001_blue", "alien002", "alien_lysper2", "alien_lysper",
    "alien_n1_bla", "alien_n1_gron", "alien_n1_lilla", "alien_n2_bla",
    "alien_n2_red", "alien_n2_green", "alien_metaballs", "alien_metaball2",
    "alien_metaball3", "alien_kuler", "alien_kuleg", "alien_kuleb", "alien_kuleo",
    "alien_kulel", "alien_mkuler", "alien_big4_1", "alien_big4_2",
    "alien_big4_3", "alien_big4_4", "alien_big4_5", "alien_big4_6",
)
PACKAGED_ENEMY_BY_RESOURCE = {
    "ALIEN001.bmp": "alien001",
    "ALIEN_2.bmp": "alien_2",
    "ALIEN_3.bmp": "alien_3",
    "ALIEN000.bmp": "alien000",
    "ALIEN_Lilla.bmp": "alien_lilla",
    "ALIEN003.bmp": "alien003",
    "ALIEN003_3.bmp": "alien003_3",
    "ALIEN_BIG1_1.bmp": "alien_big1_1",
    "ALIEN_BIG1_2.bmp": "alien_big1_2",
    "ALIEN_BIG1_3.bmp": "alien_big1_3",
    "ALIEN_BIG1_4.bmp": "alien_big1_4",
    "ALIEN_BIG1_5.bmp": "alien_big1_5",
    "ALIEN_BIG1_6.bmp": "alien_big1_6",
    "ALIEN_big2_1.bmp": "alien_big2_1",
    "ALIEN_big2_2.bmp": "alien_big2_2",
    "ALIEN_big2_3.bmp": "alien_big2_3",
    "ALIEN_big2_4.bmp": "alien_big2_4",
    "ALIEN_big2_5.bmp": "alien_big2_5",
    "ALIEN_big2_6.bmp": "alien_big2_6",
    "ALIEN_rakett.bmp": "alien_rakett",
    "ALIEN_rakett_gronn.bmp": "alien_rakett_gronn",
    "ALIEN_baller.bmp": "alien_baller",
    "ALIEN_baller2.bmp": "alien_baller2",
    "ALIEN_Green_lilla_t.bmp": "alien_green_lilla_t",
    "ALIEN_Cyan_lilla_t.bmp": "alien_cyan_lilla_t",
    "ALIEN_RaudKule.bmp": "alien_raudkule",
    "ALIEN_RaudKule2.bmp": "alien_raudkule2",
    "ALIEN_Blavinger_gf.bmp": "alien_blavinger_gf",
    "ALIEN_Blavinger_gf2.bmp": "alien_blavinger_gf2",
    "ALIEN_RBille.bmp": "alien_rbille",
    "ALIEN_gultop.bmp": "alien_gultop",
    "ALIEN_lillatop.bmp": "alien_lillatop",
    "ALIEN_bluekreps.bmp": "alien_bluekreps",
    "ALIEN_lbluekreps.bmp": "alien_lbluekreps",
    "ALIEN_brownkreps.bmp": "alien_brownkreps",
    "ALIEN_brownkreps2.bmp": "alien_brownkreps2",
    "ALIEN_gulkreps.bmp": "alien_gulkreps",
    "ALIEN_Rvinggk.bmp": "alien_rvinggk",
    "ALIEN_Gvingbk.bmp": "alien_gvingbk",
}

CAMPAIGN_ENEMY_ASSETS = {
    "alien_3.tga": {
        "size": 94292,
        "sha256": "1995f7f478ddb3d3f53c2a46d5100223f0fd12739c709427a5ee73d4f0988308",
    },
    "alien_3_mask.tga": {
        "size": 15488,
        "sha256": "163163d93f0cf86a371bfcc65273ef6daa52128ad2ae09c72f2df42a4c971668",
    },
    "alien_3.hma": {
        "size": 55296,
        "sha256": "bae7ff4e43ac9b5f3e985508b502e417462b59515b4a582d5ad8dd98d2657622",
    },
    "alien000.tga": {
        "size": 47264,
        "sha256": "3dda14d46beab0e81826a02671ebcfb5d9b7cc11762c5b7ecfe9cc2b6e963575",
    },
    "alien000_mask.tga": {
        "size": 10081,
        "sha256": "7ed361a4982a7d3560413d623c578988e21966e88c394de014f6b56245ec3f50",
    },
    "alien000.hma": {
        "size": 55296,
        "sha256": "2153c68d6529e03ffa016752d8d0e12eb67f4282b7105db3fe1651a1e86d2f56",
    },
    "alien_lilla.tga": {
        "size": 117066,
        "sha256": "0876ed4f60bdc24f3368d1a1a32e86a771df9222cf354618bef313b9cf22c321",
    },
    "alien_lilla_mask.tga": {
        "size": 15762,
        "sha256": "87358b3f98f528a5f6f278a9707d0e0c6516f8e3fe6370353774be0c6b56ad90",
    },
    "alien_lilla.hma": {
        "size": 55296,
        "sha256": "f6af03a6a15fba704e14b21be11be9908e52b5adcd372aa3612731e97622bb09",
    },
    "alien003.tga": {
        "size": 111308,
        "sha256": "96194d436940fbd69b39ae768ce44ee24fe3f0c8fff874aade7b8d0f09f67815",
    },
    "alien003_mask.tga": {
        "size": 24126,
        "sha256": "7335fae33fed27cb9322bbaa4c1c6c1b1720790aea09360ebdc5a74de25ea17b",
    },
    "alien003.hma": {
        "size": 55296,
        "sha256": "fc7d701fca04fa6f9e653bbb3295898a1a48b18aa487c19fb1595a5c27d4ba2f",
    },
    "alien003_3.tga": {
        "size": 112433,
        "sha256": "49d7e12b8d479abfbd3ec78922a620adf9adbc6a38c5f474cdb067e8ed85d1e7",
    },
    "alien003_3_mask.tga": {
        "size": 24228,
        "sha256": "cf143b6ba1f03d96a81bba0415cdd567c2276a00cbca789bd3bc02b9d840ec01",
    },
    "alien003_3.hma": {
        "size": 55296,
        "sha256": "db057c33f556e606ae51c92877fd969afa142b0d38de6fb8c88bcd14bdd6f183",
    },
    "alien_big1_1.tga": {
        "size": 104528,
        "sha256": "56a560e9822a3ca12c7dacdd1532de02a43184e6e180c5f861e6ee7176d3629d",
    },
    "alien_big1_1_mask.tga": {
        "size": 11709,
        "sha256": "d5ea2500fbfbde258ba816e37a0944cee270aaa72c3b33d8bd3f9ce3818fb0c8",
    },
    "alien_big1_1.hma": {
        "size": 55296,
        "sha256": "d43422c076f19e4a8113f3b211abdb728ac329d34535e5d8fae183cc2625daab",
    },
    "alien_big1_2.tga": {
        "size": 101648,
        "sha256": "ee77517a47966e3e9a87ef8bf5576b9f7859aab84be9adc01c4eb741d924730d",
    },
    "alien_big1_2_mask.tga": {
        "size": 9855,
        "sha256": "9e93ee77dd314663d985ec6eed1c14a978a37e125a42f846765849738082e9ab",
    },
    "alien_big1_2.hma": {
        "size": 55296,
        "sha256": "68193b9f640c1a24b012e8f33ecd5b981f6471720e6e56c8dcf08a170166acb6",
    },
    "alien_big1_3.tga": {
        "size": 101985,
        "sha256": "e0c40542f67210fa1a57bfbab9d590ca426476e0f4358e36bc0c2fabf4540b76",
    },
    "alien_big1_3_mask.tga": {
        "size": 10819,
        "sha256": "c9a55b787fb5af8e753807be37b10b5ca9834aee8e02b969c107c6abbc415df2",
    },
    "alien_big1_3.hma": {
        "size": 55296,
        "sha256": "d58d020f12d55367ef663c5d16c44f10e45dc405a12eb3b033765c07e3293484",
    },
    "alien_big1_4.tga": {
        "size": 101974,
        "sha256": "77e6dd5df6017c6fef91160a34efb572905638a182226166f34fb8b3e80fc109",
    },
    "alien_big1_4_mask.tga": {
        "size": 10718,
        "sha256": "a3d73f7608cd049f1e91e15c125b30a53dd13f243e06c8a4e27f03124287a2fd",
    },
    "alien_big1_4.hma": {
        "size": 55296,
        "sha256": "cb2e719631b6aeb5407cc6e353c551c874b1ffa3a79ad922d3772d91447e5697",
    },
    "alien_big1_5.tga": {
        "size": 101713,
        "sha256": "683673126f068c2128d2ece12f9268ae3aa930f43520f18856072cf96116d99d",
    },
    "alien_big1_5_mask.tga": {
        "size": 10876,
        "sha256": "1a10302a6c0b2ea21ce218df6dd9a7fdf1238aa7816fa6b6046e31535d68dc79",
    },
    "alien_big1_5.hma": {
        "size": 55296,
        "sha256": "f9e6c0415ee0167f25ef99dddb059cae013eb39547f1b97144a8623760542ea2",
    },
    "alien_big1_6.tga": {
        "size": 100915,
        "sha256": "780c90761a50f925d3b5a21e961b56dbb5349681228de7d0bec555381feaf0c8",
    },
    "alien_big1_6_mask.tga": {
        "size": 10728,
        "sha256": "8b6a1db9e566efd3991aec663d2f1a9a5d7c91f9590586eed9ac6ec1625da6cc",
    },
    "alien_big1_6.hma": {
        "size": 55296,
        "sha256": "fb54dc044be28919409b8ff7947db6b8195e33e1301365c9ba5f725ef128d3a1",
    },
    "alien_big2_1.tga": {
        "size": 84845,
        "sha256": "1da17e9670abbfa2bc87a9deab2b083b2b2557e2c059a1fb5dc65310898ae0ff",
    },
    "alien_big2_1_mask.tga": {
        "size": 7776,
        "sha256": "d8d7beca66758222cd6cc1add90f32e393978fe24ce99201c69e7b80cb7fa47f",
    },
    "alien_big2_1.hma": {
        "size": 55296,
        "sha256": "246f2ae2b2b98050f3e2ecb9f55be50b192fdc9ea845a07416bab7d6bc95cd7b",
    },
    "alien_big2_2.tga": {
        "size": 69331,
        "sha256": "4132e267ef0a32f339b29cdc92c6d967a5620e3580c8af329f35121eb3c1630a",
    },
    "alien_big2_2_mask.tga": {
        "size": 6715,
        "sha256": "3d9e61aa087fb4df66b5fbb89ff2783babb3890aa968c89a6f92cedfad49043b",
    },
    "alien_big2_2.hma": {
        "size": 55296,
        "sha256": "665e76e2e064381ba1718f5353d76267701fd0202836206e79714e09246cae28",
    },
    "alien_big2_3.tga": {
        "size": 69806,
        "sha256": "82293326f90147696c41e9753ecc2d187ecf82a562140cff5d87562092fa8c1b",
    },
    "alien_big2_3_mask.tga": {
        "size": 6671,
        "sha256": "4dc1cca80a57b75a8e9dbc374365f13149fc6261130073cfd5e2dc233f19ac2a",
    },
    "alien_big2_3.hma": {
        "size": 55296,
        "sha256": "871ed4f97abed103725294e5800f95566d57f28f0f91701088be6cd2dd93a9b0",
    },
    "alien_big2_4.tga": {
        "size": 68631,
        "sha256": "8674358067fe3919cc9deaac886904065ce3f8c974fa8b71e3ba7effebdec569",
    },
    "alien_big2_4_mask.tga": {
        "size": 6151,
        "sha256": "7de524d0226d39f24cd2ad7efbf94a9583965fdd45df5b71def67a22a8034c84",
    },
    "alien_big2_4.hma": {
        "size": 55296,
        "sha256": "9a76057353965b5eea3fbc0de91d97c1620d11de1a0c256467e82bbdf89ae606",
    },
    "alien_big2_5.tga": {
        "size": 69802,
        "sha256": "4f9399fd8a5c64a78ad2ef87439ca0baf0af3fa8311831495a9de07f70acd850",
    },
    "alien_big2_5_mask.tga": {
        "size": 6666,
        "sha256": "e8413ea74492ea3cffd9ab90b2de9359cc3b1c8d60f6b31ccee13f5978b6463d",
    },
    "alien_big2_5.hma": {
        "size": 55296,
        "sha256": "201b6696787ae1b5ac891d99879d4f1aba4a84b8c7976760473ed7e853a63e9e",
    },
    "alien_big2_6.tga": {
        "size": 70043,
        "sha256": "42a7f0814ad72d426c46ec2f1247d331763d460dd526b9a08f112fdc8b62a008",
    },
    "alien_big2_6_mask.tga": {
        "size": 4471,
        "sha256": "4e6b4ded4f30bd502ec76d2061d0a159601ea5b0b975506dd1dd1558ea84f8d5",
    },
    "alien_big2_6.hma": {
        "size": 55296,
        "sha256": "aa4d4ad044cdb47b047ce8a85260bfd85dae040c26e8704fdba306d680801c74",
    },
    "alien_rakett.tga": {
        "size": 66506,
        "sha256": "396194d6ef26cbc866b8ae5581c2f62e754ef543093784ae95c29adb5c075dfb",
    },
    "alien_rakett_mask.tga": {
        "size": 15101,
        "sha256": "8bb130e9ff4f155f91b7c928a37ef7f5c4c6c7164f6e73b2da954a6c8023731b",
    },
    "alien_rakett.hma": {
        "size": 55296,
        "sha256": "4a92a4d177925ffc888f69b88463a4e7b9707dbfbac96704cc1a2506e62f3c16",
    },
    "alien_rakett_gronn.tga": {
        "size": 66502,
        "sha256": "f360187200d177e614b3249c522cbb6fd68c32e44e7b67dad3a65ec18c63782b",
    },
    "alien_rakett_gronn_mask.tga": {
        "size": 15101,
        "sha256": "8bb130e9ff4f155f91b7c928a37ef7f5c4c6c7164f6e73b2da954a6c8023731b",
    },
    "alien_rakett_gronn.hma": {
        "size": 55296,
        "sha256": "f97bc6c3487944e14c7217036dfd07f8fa74aa52b212960fcee41d961315d14e",
    },
    "alien_baller.tga": {
        "size": 101734,
        "sha256": "9c6cda05951af12f208dd989661701088275fb6ef142d49a45e197bcea8a4038",
    },
    "alien_baller_mask.tga": {
        "size": 13472,
        "sha256": "8b716bd52e73f994dc527b33067fa868a006180ccead1c9d8b9d444478bd9512",
    },
    "alien_baller.hma": {
        "size": 55296,
        "sha256": "e468943e3feb12fe081f4ec0e883ef0190bb11d2b31af85054b1191f77fcb682",
    },
    "alien_baller2.tga": {
        "size": 101734,
        "sha256": "ac91e8c8e07e91cc3bfd5b77171a6344bdb77b77156cd125a6f99e2ba7e88a94",
    },
    "alien_baller2_mask.tga": {
        "size": 13472,
        "sha256": "8b716bd52e73f994dc527b33067fa868a006180ccead1c9d8b9d444478bd9512",
    },
    "alien_baller2.hma": {
        "size": 55296,
        "sha256": "71451051a9ed25fa532386f54749486369261ebd760f0d72d5d1b50f0ff6eff1",
    },
    "alien_green_lilla_t.tga": {
        "size": 100132,
        "sha256": "352688c4bcbe9b3c2c390e83f3a062dc0a263b6c93376b44db41b62afb9c52e6",
    },
    "alien_green_lilla_t_mask.tga": {
        "size": 18720,
        "sha256": "8412d1e6b4967a2d6bea11705b8fd5bcf83ce2d5ab766dc6596ef4dc117b57ba",
    },
    "alien_green_lilla_t.hma": {
        "size": 55296,
        "sha256": "6a6b95b5e6f8e2a6dc2b7e2412f583710b64914bd525bb35c9f86a655d087f37",
    },
    "alien_cyan_lilla_t.tga": {
        "size": 100044,
        "sha256": "42f4f0870cd332fb26f2bf8007f5c8601fa788469d3cc08abb981268d4f85f73",
    },
    "alien_cyan_lilla_t_mask.tga": {
        "size": 18728,
        "sha256": "a438a5e56767a797a9f56a36cf2fc5129346663cf32a727feced06da501fdd18",
    },
    "alien_cyan_lilla_t.hma": {
        "size": 55296,
        "sha256": "17491459890f98a829e8038387f3dfdd5cd640b9582f8f3ecb5efb376a2413e3",
    },
    "alien_raudkule.tga": {
        "size": 96291,
        "sha256": "b53db56ae031c8e2154f0a9e4c3d9d3c3160a98506df1f70874067100c48cf65",
    },
    "alien_raudkule_mask.tga": {
        "size": 11900,
        "sha256": "43085ebbad1497072d61f2c2b28930808d7f1a08e83f4d3799d34dfc9f9f0783",
    },
    "alien_raudkule.hma": {
        "size": 55296,
        "sha256": "0faf940cb4a0b086460a9ad24b47c65e4129855385aeb5670183014c9c65c392",
    },
    "alien_raudkule2.tga": {
        "size": 95810,
        "sha256": "0d7ec4a55c4f08bbfd99225e3295676b289be88c7163b62737e8c228cfdc1800",
    },
    "alien_raudkule2_mask.tga": {
        "size": 11850,
        "sha256": "ef576fbbe8a17bc0c25100f529e1c78506189d23f2e518746e10dfb15b88d7d1",
    },
    "alien_raudkule2.hma": {
        "size": 55296,
        "sha256": "cf0147af950232e1145469cb2cabdc72dbb68444735b2d55e1c85a33a7c220f6",
    },
    "alien_blavinger_gf.tga": {
        "size": 109469,
        "sha256": "285135115352528a29f7a1d1f692dd91c4694840127d076499f823db082941d9",
    },
    "alien_blavinger_gf_mask.tga": {
        "size": 18220,
        "sha256": "39ea71f7092f10d8c79a8c34df3e21ddf12538ea079202c4d6520b52d10c9605",
    },
    "alien_blavinger_gf.hma": {
        "size": 55296,
        "sha256": "e185d22d65ee4d87d0e6a860116789cb129c94f654cb0068c8f03249ccb9a105",
    },
    "alien_blavinger_gf2.tga": {
        "size": 110817,
        "sha256": "a745c3919f35db4e97e12ec9defc9c1cf277de1a307ffb7c8c9ff2c3e11933b7",
    },
    "alien_blavinger_gf2_mask.tga": {
        "size": 18229,
        "sha256": "02323cce179a49769950ae2619fe112b6b125af2fab261fe362d956dfc3ebd7e",
    },
    "alien_blavinger_gf2.hma": {
        "size": 55296,
        "sha256": "a3398e38ce6e1f396aca051a446c5c32d00e5ce154dbaf8c47a3d0efb1cd2d23",
    },
    "alien_rbille.tga": {
        "size": 118012,
        "sha256": "bfda091771ea721e8eaebf6fd79a862a3ea4ddf761d610c3e6b4ebcfef3b3817",
    },
    "alien_rbille_mask.tga": {
        "size": 24699,
        "sha256": "7237ff1c15cd28b43f04871d054390cc9e0a2ae887643cae870e1179d44d4105",
    },
    "alien_rbille.hma": {
        "size": 55296,
        "sha256": "383c57f8011db36f08075866393edb12f6431c92de12ab997dac8e032ade6294",
    },
    "alien_gultop.tga": {
        "size": 95935,
        "sha256": "36ac12d0da7b0827908f4fed3a0e161a56b087ffe7b664ffb116bb037d459373",
    },
    "alien_gultop_mask.tga": {
        "size": 27130,
        "sha256": "47ada695b79e978b491ab0a4af574c8c2079916da94fff1ca45d334aaaf54e42",
    },
    "alien_gultop.hma": {
        "size": 55296,
        "sha256": "9be9a59dc422cf792bd10ec5340cd7e83b7ad017eade4fd133033a4d96b38759",
    },
    "alien_lillatop.tga": {
        "size": 59994,
        "sha256": "e8be03a599212d56636ffb520c8731b1291e12a141ab569a4ef57d58cfea15b4",
    },
    "alien_lillatop_mask.tga": {
        "size": 17944,
        "sha256": "9104a16c8fdd6ad7f9bb66e804b06e806af4b5937e3c0125340b21d73e6ae6a8",
    },
    "alien_lillatop.hma": {
        "size": 55296,
        "sha256": "14399a695cea917fc993602ba5d8dbfc9647ddfa854e6aeb6ce75bc0f9ecf326",
    },
    "alien_bluekreps.tga": {
        "size": 89383,
        "sha256": "a37062a0fd23d7bd243128892862027d640722ba40483c4d35b35fa48ae04c9a",
    },
    "alien_bluekreps_mask.tga": {
        "size": 18274,
        "sha256": "8db4ca118c8a3652d83ae02372c2a5119c4511256286d8991ec8ad45bfe822de",
    },
    "alien_bluekreps.hma": {
        "size": 55296,
        "sha256": "fcd57a7eafcd429c0f86d6c75ed4ab79d292abf0574d9a6c9392259bec853c57",
    },
    "alien_lbluekreps.tga": {
        "size": 51570,
        "sha256": "1f07b2a9850da3d08010d6c780dd4e8cfebc22b2c6d7f8630c67dd05d7e16fc9",
    },
    "alien_lbluekreps_mask.tga": {
        "size": 15924,
        "sha256": "be3492b42f9dfdfb2de11bdcf922b08d1d8a98e0e6ba14d6c7e8f0df842ff605",
    },
    "alien_lbluekreps.hma": {
        "size": 55296,
        "sha256": "d6d589c097fcc7a114df3883251a2b0bf72ef28fec944a372d13d43d4672bc5a",
    },
    "alien_brownkreps.tga": {
        "size": 89381,
        "sha256": "ac39f15cf8af7ad9450b7da477bf4000403c83345fc3673e46e8f942a921ae18",
    },
    "alien_brownkreps_mask.tga": {
        "size": 18133,
        "sha256": "074973bd488356d9490f715a9ca24046a634535891df3fdc1e8e72bf1f04eb70",
    },
    "alien_brownkreps.hma": {
        "size": 55296,
        "sha256": "71fe219ecb5a77a3013dc902b40175a3270e9cf4b68c8158d783f7a262359e7e",
    },
    "alien_brownkreps2.tga": {
        "size": 89305,
        "sha256": "47afd5215df0a43b8f1535cdcbd60615a18e2181596d08802ddff6354d52d10a",
    },
    "alien_brownkreps2_mask.tga": {
        "size": 18090,
        "sha256": "be6447433b12998afb458eca58e82f49a925e5e29d0c0979410bd349720009c8",
    },
    "alien_brownkreps2.hma": {
        "size": 55296,
        "sha256": "d40cc415e55c638cf1dd3343a4a9f4d43ce45f50282054716a1a15ddbe268a4c",
    },
    "alien_gulkreps.tga": {
        "size": 50392,
        "sha256": "fe9875593cd146dc952e893e43eee11a085c9c3d8b306b13a0e3d828d6c88540",
    },
    "alien_gulkreps_mask.tga": {
        "size": 15924,
        "sha256": "be3492b42f9dfdfb2de11bdcf922b08d1d8a98e0e6ba14d6c7e8f0df842ff605",
    },
    "alien_gulkreps.hma": {
        "size": 55296,
        "sha256": "ba7622bec7cf00ae8fbd33b13c7bedd09c670cbc3db47e3f0f8cb2ea69c08b80",
    },
    "alien_rvinggk.tga": {
        "size": 132162,
        "sha256": "491de8a3383b9963b4b7c4fbba1a5aecbfbd113102e0093b3fbcfd4797b83e54",
    },
    "alien_rvinggk_mask.tga": {
        "size": 22708,
        "sha256": "34ee0bd347650c5f953321deed06f732282df894aefa91bb3d753f30115b628c",
    },
    "alien_rvinggk.hma": {
        "size": 55296,
        "sha256": "9fbe36466a3ea97d56e8fc0c3f9e8f5520a42a062371e6e847e6aecfd256e474",
    },
    "alien_gvingbk.tga": {
        "size": 86619,
        "sha256": "23c3af4e80e430f2d0522cdddbb7f9879c5f7904e8a67e2a400ad6e17b428345",
    },
    "alien_gvingbk_mask.tga": {
        "size": 19204,
        "sha256": "ed8bcc70953f230827626a300f5e60f59d8e1821e8d1cbc798c378e566f231b8",
    },
    "alien_gvingbk.hma": {
        "size": 55296,
        "sha256": "e05cdecbb41f7533624241da963741d9d0f25615c25dca1235eb75181eabc35a",
    },
}

# These bounded regions pin the LVD-loader, fixed-table consumers, mode-3
# branches, and supplemental animation path independently of the whole-file
# executable hash. Result/reward regions remain owned by bonus_modes_extract.py.
REGION_SPECS = (
    (
        "tail_score_tables_loader",
        0x00559C03,
        61,
        "8dbf993f1df6e77ed11cf8889bcc7b8f30566839fb5b4cae739170f7af174ad5",
    ),
    (
        "fixed_table_loader",
        0x0055981D,
        174,
        "435f5a5f546fa473694ceb72b91853d1ca61d490de33ce9191a0fcf595589e1d",
    ),
    (
        "ordinary_fixed_metadata_copy",
        0x0056CF60,
        60,
        "0f33f1dc8c3ab1ce9a9a5e42f126ce3b9f52c3d8a9205356676d8546d4f7a17d",
    ),
    (
        "ordinary_resource_slot_dispatch",
        0x0056BCBC,
        69,
        "b7ee94fd7f4ab47072918a3b6480579e1bca451fbe6aeea7e88e1ce8fc7622fc",
    ),
    (
        "ordinary_resource_slot_1_score_copy",
        0x0056BDA6,
        41,
        "9503b3ee7504da49944da5d025fa59f7b40daca541d4c2a85f6759df435a9f41",
    ),
    (
        "ordinary_resource_slot_2_score_copy",
        0x0056BFE7,
        41,
        "0055ff8dc090ecba4ecdb5bee30975078edb64f035099bea5f7345069d91f2a8",
    ),
    (
        "supplemental_record_loop",
        0x0056D468,
        227,
        "752c4fdd2ed4648720e4ac87326be68369e42081ff92fe2875e8992a9aa4603a",
    ),
    (
        "supplemental_common_state_6_init",
        0x0056E23C,
        646,
        "cc4c556a01514b57127e7cf11dd6c075c3746c2642983518c9cb0f657b2cf7f2",
    ),
    (
        "supplemental_record_fields",
        0x0056E4C2,
        381,
        "72e4360d90cfb1c14148149a620af96851671c1324d51921b3015518070ddb90",
    ),
    (
        "supplemental_animation_fields",
        0x0056E63F,
        546,
        "f185cbd9a3d602b27c246e9731243abc4b64e9e14d3b507c4481a75a631d8968",
    ),
    (
        "supplemental_animation_limit_init",
        0x0056E80E,
        83,
        "87f2192d1f78eb32be9d5cd48132a904c63c66d5c1877358c705788e55a5e441",
    ),
    (
        "state_6_source_and_phase_update",
        0x0060F90B,
        1001,
        "1d48b4ff25fe48c8682402ee95b9e0dfe97d36a88f9a47912bafd8d670dda9fe",
    ),
    (
        "state_6_renderer_rect_load",
        0x0061924D,
        191,
        "6a07966ec67f44649c10f6e4f359856ac5c943fbfea3d1e25883ce0d2be2c5ab",
    ),
    (
        "special_mode_classifier",
        0x005523EE,
        56,
        "65b15500890b59311c14d5016e33505673c7469917e19a0149559200098540be",
    ),
    (
        "mode_3_loader_entity_count",
        0x0056D3CE,
        22,
        "dce803bb1a9d37508a07e5d5b36afdbd5732933fe74188b5278d52ae3c05c31e",
    ),
    (
        "mode_3_auxiliary_gate_a",
        0x00581276,
        39,
        "be3b9eea3e7423794733542562f6271abb5d245400e38cb41ab35be7d332013e",
    ),
    (
        "mode_3_auxiliary_gate_b",
        0x005819E9,
        61,
        "bb274b6008a59ee1e1d7ecf13424e08cd639b0e5349743688cb827e4a75babad",
    ),
    (
        "mode_3_auxiliary_gate_c",
        0x0058E397,
        63,
        "c6f7d49831bdbe5b83bc06ae46bb146380d0e864bcf60ad3d0bf4b88b999d5fa",
    ),
    (
        "mode_3_alien_shot_suppression",
        0x006077AC,
        38,
        "6b56968191820ca12c1d091299716f7cadb2eadf0ee2f5caf23c6591229afa65",
    ),
    (
        "terminal_opcode_6_mode_split",
        0x00608C80,
        27,
        "376f9c20c708fff4b4e1c06d95f653f05c1eb782047a5b51772bd6c259f85436",
    ),
    (
        "terminal_opcode_6_non_mode_2",
        0x00608DD1,
        121,
        "75925d13d020517a8427061cc459bf1a01811d93621b7cefb0fb8e39c74dc0e2",
    ),
    (
        "level_mode_setup_dispatch",
        0x0056AEE1,
        773,
        "ec17558bd4e8ced93c955a3d38ac2d8dc19740e5c475aa7c81a3c33fb7f1475b",
    ),
    (
        "level_mode_setup_jump_table",
        0x0056E900,
        24,
        "c17f4541351ac3c7abe548ebb44bde4317a5201fab0ba6767c6c0cd867e39e96",
    ),
    (
        "path_terminal_dispatch",
        0x00608A5D,
        484,
        "5a6bae35cbe849198dada2046ccca879424e7d8939c7916524e6a82f8c45dae7",
    ),
    (
        "path_terminal_jump_table",
        0x00614A58,
        24,
        "2b883c96a51e5524464d8582b3fe370e954ebd8ab9c36a4332804aa27d5c35db",
    ),
    (
        "ordinary_projectile_aim_and_speed",
        0x00607934,
        262,
        "37b0c5ac1f7c5f59988a6a680d7ab43a00fe7393b7700a07e7eb317a03188e40",
    ),
)

COMPATIBILITY_WAVE = {
    "start_tick": 60,
    "count": 8,
    "columns": 8,
    "spawn_x": 120,
    "spawn_y": -32,
    "spacing_x": 64,
    "spacing_y": 38,
    "health_fp": 65536,
    "speed_fp": 65536,
    "path": "sine_entry",
    "fire_interval_ticks": 150,
    "projectile_speed_fp": 196608,
    "score": 10,
    "cash": 2,
    "content_status": "predecessor_compatibility",
}

AUTHORED_RUNTIME = {
    # The ordinary state records are initialized with a 1.0 movement scalar.
    # This field deliberately separates supported authored play from the
    # synthetic predecessor wave retained below for v1-v8 readers.
    "ordinary_speed_fp": 65536,
}

LEVEL_MODE_RUNTIME = {
    "6": {
        "entry_state_id": 2,
        "special_mode_classifier": False,
        "ordinary_projectile_aim": {
            "enabled": True,
            "horizontal_speed_magnitude_rng_fp": [0, 98304],
            "direction": "toward_active_player_x_side",
            "tick_scale_applied": True,
        },
        "ordinary_projectile_vertical_speed": {
            "base_multiplier_fp": 65536,
            "accelerated_multiplier_fp": 81920,
            "accelerated_when_level_strictly_above": 500,
        },
        "terminal_opcode_6": "deactivate",
        "setup_flags": {
            "aimed_shots": "0x008f201d",
            "accelerated_shots": "0x008f201e",
        },
        "evidence": {
            "level_mode_global_va": "0x00a95c20",
            "setup_dispatch_region": "level_mode_setup_dispatch",
            "setup_jump_table_region": "level_mode_setup_jump_table",
            "terminal_dispatch_region": "path_terminal_dispatch",
            "terminal_jump_table_region": "path_terminal_jump_table",
            "aim_and_speed_consumer_region": "ordinary_projectile_aim_and_speed",
        },
    }
}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hex(value: int) -> str:
    return f"0x{value:08x}"


def _load_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _verify_region(image: PEImage, spec: tuple[str, int, int, str]) -> dict[str, Any]:
    name, va, size, expected_sha256 = spec
    payload = image.bytes_at(va, size)
    actual_sha256 = _sha256(payload)
    if actual_sha256 != expected_sha256:
        raise ValueError(
            f"executable byte drift in {name} at {_hex(va)}: "
            f"expected {expected_sha256}, found {actual_sha256}"
        )
    return {
        "name": name,
        "va": _hex(va),
        "size": size,
        "sha256": actual_sha256,
    }


def _verify_campaign_enemy_assets(
    enemy_dir: Path, provenance: dict[str, Any]
) -> list[dict[str, Any]]:
    provenance_assets = provenance.get("assets")
    if not isinstance(provenance_assets, list):
        raise ValueError("provenance manifest assets must be an array")
    pinned_assets = {
        asset.get("output"): asset
        for asset in provenance_assets
        if isinstance(asset, dict) and asset.get("category") == "enemy_sprite"
    }
    expected_names = tuple(
        name
        for sheet_id in EXPECTED_ENEMY_SHEET_IDS
        for name in (f"{sheet_id}.tga", f"{sheet_id}_mask.tga", f"{sheet_id}.hma")
    )
    expected_outputs = {f"textures/enemies/{name}" for name in expected_names}
    if set(pinned_assets) != expected_outputs:
        missing = sorted(expected_outputs - set(pinned_assets))
        extra = sorted(set(pinned_assets) - expected_outputs)
        raise ValueError(
            "provenance enemy inventory drift: "
            f"missing={missing}, extra={extra}"
        )
    records: list[dict[str, Any]] = []
    for name in expected_names:
        pinned = pinned_assets[f"textures/enemies/{name}"]
        expected = {
            "size": pinned.get("size"),
            "sha256": pinned.get("output_sha256"),
        }
        path = enemy_dir / name
        if not path.is_file():
            raise ValueError(f"missing extracted campaign enemy asset: {path}")
        payload = path.read_bytes()
        actual = {"size": len(payload), "sha256": _sha256(payload)}
        if actual != expected:
            raise ValueError(
                f"campaign enemy asset drift for {name}: "
                f"expected {expected}, found {actual}"
            )
        if name.endswith(".hma"):
            if len(payload) != 576 * 96 or set(payload) - {0, 1}:
                raise ValueError(f"{name} must be a 576x96 binary occupancy mask")
        if name == "alien000.hma":
            occupied = [
                (x - 384, y)
                for y in range(64)
                for x in range(384, 448)
                if payload[y * 576 + x]
            ]
            bounds = [
                min(x for x, _ in occupied),
                min(y for _, y in occupied),
                max(x for x, _ in occupied),
                max(y for _, y in occupied),
            ]
            if len(occupied) != 1123 or bounds != [0, 0, 61, 38]:
                raise ValueError("alien000 supplemental frame 6 occupancy drift")
        if name == "alien003.hma":
            occupied = [
                (x - 384, y)
                for y in range(64)
                for x in range(384, 448)
                if payload[y * 576 + x]
            ]
            bounds = [
                min(x for x, _ in occupied),
                min(y for _, y in occupied),
                max(x for x, _ in occupied),
                max(y for _, y in occupied),
            ]
            if len(occupied) != 1424 or bounds != [2, 2, 61, 60]:
                raise ValueError("alien003 supplemental frame 6 occupancy drift")
        if name == "alien_rakett.hma":
            occupied = [
                (x - 192, y)
                for y in range(64)
                for x in range(192, 256)
                if payload[y * 576 + x]
            ]
            bounds = [
                min(x for x, _ in occupied),
                min(y for _, y in occupied),
                max(x for x, _ in occupied),
                max(y for _, y in occupied),
            ]
            if len(occupied) != 1044 or bounds != [17, 1, 46, 61]:
                raise ValueError("alien_rakett supplemental frame 3 occupancy drift")
        if name == "alien_baller.hma":
            occupied = [
                (x - 192, y)
                for y in range(64)
                for x in range(192, 256)
                if payload[y * 576 + x]
            ]
            bounds = [
                min(x for x, _ in occupied),
                min(y for _, y in occupied),
                max(x for x, _ in occupied),
                max(y for _, y in occupied),
            ]
            if len(occupied) != 1817 or bounds != [5, 2, 58, 59]:
                raise ValueError("alien_baller supplemental frame 3 occupancy drift")
        records.append(
            {
                "path": f"assets/original/textures/enemies/{name}",
                **actual,
            }
        )
    return records


def _enemy_resources(document: dict[str, Any]) -> list[dict[str, Any]]:
    score_words = document["unresolved_tail_array_a"]["raw_words"]
    resources: list[dict[str, Any]] = []
    for slot in document["resource_slots"][:6]:
        raw_name = slot["text_cp1252"]
        if not raw_name:
            continue
        resource_slot_id = slot["index"] + 1
        normalized_sheet_id = Path(raw_name).stem.casefold()
        enemy_sheet_id = PACKAGED_ENEMY_BY_RESOURCE.get(
            raw_name, normalized_sheet_id
        )
        if enemy_sheet_id != normalized_sheet_id:
            raise ValueError(f"enemy resource normalization drift for {raw_name!r}")
        if enemy_sheet_id not in EXPECTED_ENEMY_SHEET_IDS:
            raise ValueError(f"unsupported enemy resource {raw_name!r}")
        resources.append(
            {
                "resource_slot_id": resource_slot_id,
                "raw_name": raw_name,
                "enemy_sheet_id": enemy_sheet_id,
                "kill_score": score_words[resource_slot_id - 1],
            }
        )
    return resources


def _authored_lvd(document: dict[str, Any], level_id: int) -> dict[str, Any]:
    groups: list[dict[str, Any]] = []
    for source_group in document["active_groups"]:
        groups.append(
            {
                "id": source_group["index"],
                "entry_origin_x": source_group["entry_origin_x"],
                "entry_origin_y": source_group["entry_origin_y"],
                "first_activation_delay_ticks": source_group[
                    "first_activation_delay_ticks"
                ],
                "activation_stagger_ticks": source_group["activation_stagger_ticks"],
                "initial_velocity_x_milli": source_group[
                    "initial_velocity_x_milli"
                ],
                "initial_velocity_y_milli": source_group[
                    "initial_velocity_y_milli"
                ],
                "kill_cohort_id": source_group["kill_cohort_id"],
                "group_mode_id": source_group["group_mode_id"],
                "enemies": [
                    {
                        "id": enemy["index"],
                        "formation_target_x": enemy["formation_target_x"],
                        "formation_target_y": enemy["formation_target_y"],
                        "resource_slot_id": enemy["resource_slot_id"],
                        "base_health": enemy["base_health"],
                        "behavior_timer_a_initial": enemy[
                            "behavior_timer_a_initial"
                        ],
                        "behavior_timer_a_step": enemy["behavior_timer_a_step"],
                        "behavior_timer_b_initial": enemy[
                            "behavior_timer_b_initial"
                        ],
                        "behavior_timer_b_step": enemy["behavior_timer_b_step"],
                    }
                    for enemy in source_group["enemies"]
                ],
                "path_points": [
                    {
                        "id": point["index"],
                        "acceleration_x_milli": point["acceleration_x_milli"],
                        "acceleration_y_milli": point["acceleration_y_milli"],
                        "opcode": point["opcode"],
                        "unknown_0c": point["unknown_0c"],
                        "duration_threshold_ticks": point[
                            "duration_threshold_ticks"
                        ],
                    }
                    for point in source_group["path_points"]
                ],
            }
        )
    return {
        "schema": "warblade.lvd.authored.v2",
        "source_title_cp1252": document["summary"]["title"],
        "level_mode_id": document["summary"]["level_mode_id"],
        "logical_width": 800,
        "mirror_x": bool((level_id // 100) & 1),
        "supplemental_spawn_records_raw_words": document["global_header"][
            "supplemental_spawn_records_raw_words"
        ],
        "fixed_table_records_raw_words": [
            record["raw_words"]
            for record in document["unresolved_fixed_table"]["records"]
        ],
        "groups": groups,
    }


def _decode_levels(
    levels_dir: Path, facts: dict[str, Any]
) -> tuple[dict[int, dict[str, Any]], list[dict[str, Any]]]:
    fact_levels = facts.get("levels")
    if not isinstance(fact_levels, list):
        raise ValueError("known_facts.json levels must be an array")
    fact_ids = tuple(item.get("id") for item in fact_levels if isinstance(item, dict))
    if fact_ids != EXPECTED_LEVEL_IDS:
        raise ValueError(
            "known_facts.json must contain ordered classic levels 1 through 100"
        )
    facts_by_id = {item["id"]: item for item in fact_levels}
    documents: dict[int, dict[str, Any]] = {}
    summaries: list[dict[str, Any]] = []
    for level_id in EXPECTED_LEVEL_IDS:
        fact = facts_by_id.get(level_id)
        if not isinstance(fact, dict):
            raise ValueError(f"known_facts.json is missing classic level {level_id}")
        expected_name = f"classic_level_{level_id:03}.lvd"
        if fact.get("archive_member") != expected_name:
            raise ValueError(f"classic level {level_id} archive member is not canonical")
        path = levels_dir / expected_name
        payload = path.read_bytes()
        actual_sha256 = _sha256(payload)
        if fact.get("sha256") != actual_sha256:
            raise ValueError(f"retail LVD hash drift for level {level_id}")
        if fact.get("size") != len(payload) or len(payload) != lvd_decoder.FILE_SIZE:
            raise ValueError(f"retail LVD size drift for level {level_id}")
        document = lvd_decoder.decode_blob(payload, str(path))
        if lvd_decoder.encode_document(document) != payload:
            raise ValueError(f"lossless LVD round trip failed for level {level_id}")
        documents[level_id] = document

        summary = document["summary"]
        supplemental = document["global_header"][
            "supplemental_spawn_records_raw_words"
        ]
        # The retail supplemental loop consumes records 0 through 3. The fifth
        # raw record remains preserved in authored/lossless data but is not an
        # executable spawn source.
        resolved_entities = summary["authored_enemy_count"] + sum(
            max(0, record[0]) for record in supplemental[:4]
        )
        paths = [group["active_path_point_count"] for group in document["active_groups"]]
        resources = _enemy_resources(document)
        if not resources:
            raise ValueError(f"classic level {level_id} has no enemy resources")
        resource = resources[0]["raw_name"]
        if (
            fact.get("title") != summary["title"]
            or fact.get("author") != summary["author"]
            or fact.get("raw_enemy_reference") != resource
        ):
            raise ValueError(f"known facts diverge from decoded metadata for level {level_id}")
        if fact.get("packaged_enemy_id") != resources[0]["enemy_sheet_id"]:
            raise ValueError(f"packaged enemy binding drift for classic level {level_id}")
        if "enemy_resources" in fact and fact["enemy_resources"] != resources:
            raise ValueError(
                f"known resource bindings diverge from classic level {level_id}"
            )
        if fact.get("shop_after") != (level_id in EXPECTED_SHOP_LEVEL_IDS):
            raise ValueError(f"shop boundary drift for classic level {level_id}")

        fixed_records = [
            record["raw_words"]
            for record in document["unresolved_fixed_table"]["records"]
        ]
        if len(fixed_records) != 50 or any(
            len(record) != 4 for record in fixed_records
        ):
            raise ValueError(f"fixed table shape drift for classic level {level_id}")

        opcode_counts = Counter(
            point["opcode"]
            for group in document["active_groups"]
            for point in group["path_points"]
        )
        if level_id >= 51:
            expected_level_mode = EXPECTED_LEVEL_MODES_51_100[level_id]
            if summary["level_mode_id"] != expected_level_mode:
                raise ValueError(
                    f"classic level {level_id} mode drift: expected "
                    f"{expected_level_mode}, found {summary['level_mode_id']}"
                )
            group_mode_sequence = [
                group["group_mode_id"] for group in document["active_groups"]
            ]
            if level_id == 75:
                expected_group_modes = [4, 5, 6, 7, 7]
                allowed_opcodes = {0, 1, 2, 3, 7}
            elif level_id == 100:
                expected_group_modes = [4, 5, 6, 6, 7, 7]
                allowed_opcodes = {0, 1, 2, 6, 7}
            elif level_id == 80:
                expected_group_modes = [3, 3, 1, 1, 1, 1, 1, 1, 1, 1]
                allowed_opcodes = {0, 1, 6}
            else:
                expected_group_modes = [1] * summary["active_group_count"]
                allowed_opcodes = {0, 1, 6}
            if group_mode_sequence != expected_group_modes:
                raise ValueError(
                    f"classic level {level_id} group-mode drift: expected "
                    f"{expected_group_modes}, found {group_mode_sequence}"
                )
            if level_id == 94:
                allowed_opcodes = {0, 1, 2, 6}
            unsupported_opcodes = set(opcode_counts) - allowed_opcodes
            if unsupported_opcodes:
                raise ValueError(
                    f"classic level {level_id} uses unsupported path opcodes "
                    f"{sorted(unsupported_opcodes)}"
                )
        summaries.append(
            {
                "level": level_id,
                "lvd_path": f"assets/original/levels/{path.name}",
                "lvd_sha256": actual_sha256,
                "lvd_size": len(payload),
                "lossless_round_trip_exact": True,
                "title_cp1252": summary["title"],
                "author_cp1252": summary["author"],
                "level_mode_id": summary["level_mode_id"],
                "active_group_count": summary["active_group_count"],
                "group_enemy_counts": [
                    group["active_enemy_count"]
                    for group in document["active_groups"]
                ],
                "authored_enemy_count": summary["authored_enemy_count"],
                "resolved_entity_count": resolved_entities,
                "path_point_counts": paths,
                "path_opcode_counts": {
                    str(opcode): count for opcode, count in sorted(opcode_counts.items())
                },
                "group_mode_ids": sorted(
                    {group["group_mode_id"] for group in document["active_groups"]}
                ),
                "group_mode_sequence": [
                    group["group_mode_id"] for group in document["active_groups"]
                ],
                "kill_cohort_ids": sorted(
                    {group["kill_cohort_id"] for group in document["active_groups"]}
                ),
                "first_resource": resource,
                "packaged_enemy_id": fact["packaged_enemy_id"],
                "enemy_resources": resources,
                "shop_after": fact["shop_after"],
                "supplemental_spawn_records_raw_words": supplemental,
                "ordinary_state_four_score": document["unresolved_tail_array_a"][
                    "raw_words"
                ][0],
                "ordinary_state_four_scores_by_resource": [
                    resource["kill_score"] for resource in resources
                ],
                "tail_a_raw_words": document["unresolved_tail_array_a"]["raw_words"],
                "tail_b_raw_words": document["unresolved_tail_array_b"]["raw_words"],
                "fixed_table_records_raw_words": fixed_records,
                "nonzero_fixed_table_records": [
                    {
                        "index": record["index"],
                        "raw_words": record["raw_words"],
                    }
                    for record in document["unresolved_fixed_table"]["records"]
                    if any(record["raw_words"])
                ],
            }
        )
    return documents, summaries


def _managed_level_entry(
    level_id: int, fact: dict[str, Any], document: dict[str, Any]
) -> dict[str, Any]:
    enemy_resources = _enemy_resources(document)
    slot_one = enemy_resources[0]
    return {
        "id": level_id,
        "title": fact["title"],
        "author": fact["author"],
        "enemy_resources": enemy_resources,
        "enemy_sprite": slot_one["enemy_sheet_id"],
        "ordinary_kill_score": slot_one["kill_score"],
        "shop_after": fact["shop_after"],
        "raw_lvd": (
            f"res://assets/original/levels/classic_level_{level_id:03}.lvd"
        ),
        "raw_lvd_sha256": fact["sha256"],
        "authored_runtime": copy.deepcopy(AUTHORED_RUNTIME),
        "waves": [copy.deepcopy(COMPATIBILITY_WAVE)],
        "authored_lvd": _authored_lvd(document, level_id),
    }


def build_outputs(
    exe_path: Path,
    levels_dir: Path,
    enemy_dir: Path,
    facts_path: Path,
    level_content_path: Path,
) -> dict[Path, bytes]:
    facts = _load_object(facts_path)
    level_content = _load_object(level_content_path)
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise ValueError(
            f"retail executable SHA-256 drift: expected {WARBLADE_EXE_SHA256}, "
            f"found {image.sha256}"
        )

    documents, summaries = _decode_levels(levels_dir, facts)
    facts_by_id = {item["id"]: item for item in facts["levels"]}
    provenance = _load_object(DEFAULT_PROVENANCE)
    if level_content.get("version") not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10):
        raise ValueError(
            "levels.json input must use readable version 1 through 10"
        )
    generated_levels = [
        _managed_level_entry(level_id, facts_by_id[level_id], documents[level_id])
        for level_id in EXPECTED_LEVEL_IDS
    ]
    generated_content = {
        "version": 10,
        "schema": "warblade.levels.v10",
        "content_status": (
            "Classic levels 1-100 authored LVD groups, paths, enemy states, fixed "
            "tables, per-resource ordinary kill scores, and ordinary runtime "
            "speed are source-backed. Legacy waves are predecessor-read "
            "compatibility data and have no v10 authored runtime consumer. "
            "The v10 catalog additionally requires content/time_trial.json and "
            "sprite_frames.json v11 for retail match mode 6."
        ),
        "level_mode_runtime": copy.deepcopy(LEVEL_MODE_RUNTIME),
        "levels": generated_levels,
    }

    used_sheet_ids: list[str] = []
    for level_id in EXPECTED_LEVEL_IDS:
        for resource in _enemy_resources(documents[level_id]):
            sheet_id = resource["enemy_sheet_id"]
            if sheet_id not in used_sheet_ids:
                used_sheet_ids.append(sheet_id)
    if tuple(used_sheet_ids) != EXPECTED_ENEMY_SHEET_IDS:
        raise ValueError(
            "campaign enemy sheet inventory/order drift: "
            f"expected {EXPECTED_ENEMY_SHEET_IDS}, found {tuple(used_sheet_ids)}"
        )
    alien_assets = _verify_campaign_enemy_assets(enemy_dir, provenance)
    regions = [_verify_region(image, spec) for spec in REGION_SPECS]
    evidence = {
        "schema": "warblade.classic-levels.evidence.v10",
        "version": 10,
        "source": {
            "exe_sha256": image.sha256,
            "address_space": "32-bit PE virtual addresses",
            "lvd_directory": "assets/original/levels",
            "lossless_schema": "warblade.lvd.lossless.v1",
            "authored_schema": "warblade.lvd.authored.v2",
        },
        "levels": summaries,
        "campaign_enemy_assets": alien_assets,
        "authored_runtime": copy.deepcopy(AUTHORED_RUNTIME),
        "level_mode_runtime": copy.deepcopy(LEVEL_MODE_RUNTIME),
        "late_level_exceptions": {
            "level_80_group_modes": {
                "level_mode_id": 1,
                "group_mode_sequence": [3, 3, 1, 1, 1, 1, 1, 1, 1, 1],
                "scope": "only groups 0 and 1 use authored group mode 3",
            },
            "level_94_opcode_2": {
                "level_mode_id": 1,
                "allowed_only_on_level": 94,
                "path_opcode_counts": summaries[93]["path_opcode_counts"],
            },
        },
        "fixed_table_contract": {
            "record_count": 50,
            "words_per_record": 4,
            "authored_field": "fixed_table_records_raw_words",
            "consumer_status": "proven_from_pinned_retail_executable_regions",
            "ordinary_animation_metadata": (
                "Fixed record 0 word 1 is copied to each ordinary authored enemy."
            ),
            "supplemental_same_index_fields": {
                "fixed_word_0": "animation maximum plus one",
                "fixed_word_1": "animation metadata/bounce flag",
                "supplemental_word_2": "health and divisor numerator; divisor is word 2 / 10.0",
                "supplemental_word_3": "timer A initial",
                "supplemental_word_4": "timer A step",
            },
            "active_supplemental_levels": list(EXPECTED_SUPPLEMENTAL_LEVEL_IDS),
            "active_supplemental_records": {
                str(level_id): [
                    {
                        "record_index": record_index,
                        "raw_words": raw_words,
                        "fixed_record_raw_words": documents[level_id][
                            "unresolved_fixed_table"
                        ]["records"][record_index]["raw_words"],
                    }
                    for record_index, raw_words in enumerate(
                        documents[level_id]["global_header"][
                            "supplemental_spawn_records_raw_words"
                        ][:4]
                    )
                    if raw_words[0] > 0
                ]
                for level_id in EXPECTED_SUPPLEMENTAL_LEVEL_IDS
            },
        },
        "level_15_supplemental_frame_6": {
            "fixed_record_0": [7, 0, 0, 0],
            "animation_max_phase": 6,
            "source_rect": [384, 0, 64, 64],
            "alien000_hma_occupied_pixel_count": 1123,
            "alien000_hma_local_inclusive_bounds": [0, 0, 61, 38],
            "status": "proven_from_lvd_executable_consumer_and_asset_bytes",
        },
        "level_23_supplemental_frame_6": {
            "supplemental_record_0": [2, 1, 60, 1312, 29],
            "fixed_record_0": [7, 1, 0, 0],
            "animation_max_phase": 6,
            "animation_metadata": 1,
            "source_rect": [384, 0, 64, 64],
            "alien003_hma_occupied_pixel_count": 1424,
            "alien003_hma_local_inclusive_bounds": [2, 2, 61, 60],
            "status": "proven_from_lvd_executable_consumer_and_asset_bytes",
        },
        "level_28_supplemental_frame_3": {
            "supplemental_record_0": [2, 1, 30, 560, 7],
            "fixed_record_0": [4, 0, 0, 0],
            "animation_max_phase": 3,
            "animation_metadata": 0,
            "source_rect": [192, 0, 64, 64],
            "alien_rakett_hma_occupied_pixel_count": 1044,
            "alien_rakett_hma_local_inclusive_bounds": [17, 1, 46, 61],
            "status": "proven_from_lvd_executable_consumer_and_asset_bytes",
        },
        "level_32_supplemental_frame_3": {
            "supplemental_record_0": [3, 1, 40, 1076, 30],
            "fixed_record_0": [4, 0, 0, 0],
            "animation_max_phase": 3,
            "animation_metadata": 0,
            "source_rect": [192, 0, 64, 64],
            "alien_baller_hma_occupied_pixel_count": 1817,
            "alien_baller_hma_local_inclusive_bounds": [5, 2, 58, 59],
            "status": "proven_from_lvd_executable_consumer_and_asset_bytes",
        },
        "resource_score_table_contract": {
            "lvd_field": "unresolved_tail_array_a.raw_words",
            "resource_slot_dispatch_va": "0x0056bcbc-0x0056bd00",
            "slot_1_score_copy_va": "0x0056bda6-0x0056bdce",
            "slot_2_score_copy_va": "0x0056bfe7-0x0056c00f",
            "enemy_award_fields_va": ["0x00849bb8", "0x00849bbc"],
            "levels_21_through_23": {
                "resource_slot_1": {
                    "raw_name": "ALIEN003.bmp",
                    "enemy_sheet_id": "alien003",
                    "kill_score": 200,
                },
                "resource_slot_2": {
                    "raw_name": "ALIEN003_3.bmp",
                    "enemy_sheet_id": "alien003_3",
                    "kill_score": 300,
                },
            },
            "levels_26_through_30": {
                "rocket_family": [
                    {
                        "resource_slot_id": 1,
                        "raw_name": "ALIEN_rakett.bmp",
                        "enemy_sheet_id": "alien_rakett",
                        "kill_scores_by_level": {
                            "26": 300,
                            "27": 300,
                            "28": 300,
                            "29": 400,
                        },
                    },
                    {
                        "resource_slot_id": 2,
                        "raw_name": "ALIEN_rakett_gronn.bmp",
                        "enemy_sheet_id": "alien_rakett_gronn",
                        "kill_scores_by_level": {
                            "26": 400,
                            "27": 400,
                            "28": 400,
                            "29": 400,
                        },
                    },
                ],
                "baller_family": [
                    {
                        "resource_slot_id": 1,
                        "raw_name": "ALIEN_baller.bmp",
                        "enemy_sheet_id": "alien_baller",
                        "kill_score": 500,
                    },
                    {
                        "resource_slot_id": 2,
                        "raw_name": "ALIEN_baller2.bmp",
                        "enemy_sheet_id": "alien_baller2",
                        "kill_score": 600,
                    },
                ],
            },
            "levels_31_through_35": {
                "baller_family": [
                    {
                        "resource_slot_id": 1,
                        "raw_name": "ALIEN_baller.bmp",
                        "enemy_sheet_id": "alien_baller",
                        "kill_score": 500,
                        "level_ids": [31, 32, 33],
                    },
                    {
                        "resource_slot_id": 2,
                        "raw_name": "ALIEN_baller2.bmp",
                        "enemy_sheet_id": "alien_baller2",
                        "kill_score": 600,
                        "level_ids": [31, 32, 33],
                    },
                ],
                "lilla_t_family": [
                    {
                        "resource_slot_id": 1,
                        "raw_name": "ALIEN_Green_lilla_t.bmp",
                        "enemy_sheet_id": "alien_green_lilla_t",
                        "kill_score": 450,
                        "level_ids": [34, 35],
                    },
                    {
                        "resource_slot_id": 2,
                        "raw_name": "ALIEN_Cyan_lilla_t.bmp",
                        "enemy_sheet_id": "alien_cyan_lilla_t",
                        "kill_score": 550,
                        "level_ids": [34, 35],
                    },
                ],
            },
            "levels_36_through_100": {
                str(level_id): _enemy_resources(documents[level_id])
                for level_id in range(36, 101)
            },
            "rule": (
                "The authored resource slot is decremented into a six-case switch; "
                "each case copies its matching tail-A word into the enemy award "
                "fields. Slot 2 never falls back to slot 1."
            ),
            "status": "proven_from_lvd_and_pinned_retail_executable_regions",
        },
        "mode_3": {
            "level_ids": list(EXPECTED_MODE_THREE_LEVEL_IDS),
            "authored_target_counts": {
                str(level_id): documents[level_id]["summary"]["authored_enemy_count"]
                for level_id in EXPECTED_MODE_THREE_LEVEL_IDS
            },
            "resource_target_counts_by_level": {
                str(level_id): {
                    str(resource_slot_id): count
                    for resource_slot_id, count in sorted(
                        Counter(
                            enemy["resource_slot_id"]
                            for group in documents[level_id]["active_groups"]
                            for enemy in group["enemies"]
                        ).items()
                    )
                }
                for level_id in EXPECTED_MODE_THREE_LEVEL_IDS
            },
            "level_33_resource_target_counts": {"1": 15, "2": 15},
            "special_mode_classifier_va": "0x005523fb-0x0055241f",
            "loader_entity_counter_va": "0x0056d3ce-0x0056d3e3",
            "loader_entity_counter_global_va": "0x00e1140c",
            "alien_shot_suppression_va": "0x006077c5-0x006077d1",
            "terminal_opcode": 6,
            "terminal_mode_split_va": "0x00608c80-0x00608c9a",
            "non_mode_2_deactivation_va": "0x00608dd1-0x00608e1a",
            "mode_3_group_total_clear_va": "0x00608e1b-0x00608e49",
            "group_total_base_va": "0x00d59fc0",
            "proven_rules": [
                "Mode 3 is classified with modes 2 and 4 by the bounded special-mode helper.",
                "The loader increments one dedicated global counter for each authored mode-3 enemy.",
                "The ordinary alien-shot path branches around allocation when the level mode is 3.",
                "Terminal opcode 6 enters state 10 only in mode 2; non-mode-2 entities are deactivated.",
                "After a mode-3 opcode-6 deactivation, the entity's group-total slot is cleared.",
            ],
            "auxiliary_mode_3_early_exit_vas": [
                "0x00581286",
                "0x00581a19",
                "0x0058e3c9",
            ],
            "authoritative_result_contract": "content/bonus_modes.json#mode_three_bonus",
            "additional_pinned_regions": (
                "docs/evidence/BONUS_MODES.md and content/bonus_modes.json "
                "source.verified_regions"
            ),
        },
        "shop_boundaries": {
            "level_ids": list(EXPECTED_SHOP_LEVEL_IDS),
            "cadence": 4,
            "basis": (
                "The pinned retail manual states that every fourth level has a shop; "
                "the executable result flow applies the same boundary after Warp."
            ),
        },
        "campaign_presentation_contract": {
            "background": (
                "Levels 1-25 select stars1, levels 26-50 select stars2, and "
                "levels 51-75 select stars3. Levels 76-99 select stars4; level "
                "100 has remainder zero and selects stars1 under the retail "
                "modulo-100 selector."
            ),
            "background_selector_va": "0x00569d56-0x00569ddc",
            "enemy_sheet_ids": list(EXPECTED_ENEMY_SHEET_IDS),
            "authoritative_contract": "content/sprite_frames.json#enemy_projectile_contracts",
            "new_sheet_projectile_broad_phase_status": (
                "Executable broad-phase metadata for every enemy resource must "
                "remain separately pinned; HMA occupancy is not a substitute."
            ),
        },
        "level_25_big_boss_source": {
            "contract_id": "retail_big_boss_v1",
            "level_mode_id": 4,
            "lvd_sha256": facts_by_id[25]["sha256"],
            "authored_group_count": documents[25]["summary"]["active_group_count"],
            "authored_enemy_count": documents[25]["summary"]["authored_enemy_count"],
            "enemy_resources": _enemy_resources(documents[25]),
            "supplemental_spawn_records_raw_words": documents[25]["global_header"][
                "supplemental_spawn_records_raw_words"
            ],
            "tail_a_raw_words": documents[25]["unresolved_tail_array_a"]["raw_words"],
            "tail_b_raw_words": documents[25]["unresolved_tail_array_b"]["raw_words"],
            "gameplay_contract_status": "exact_state_13_trace_complete",
            "exact_trace_complete": True,
            "authoritative_contract": "content/bosses.json#bosses.retail_big_boss_v1",
            "trace_entry_points": {
                "init": "0x00569260",
                "update": "0x00605fe0",
                "collision": "0x00585840",
                "mark": "0x00555c40",
                "dispatcher": "0x005afc50",
                "renderer": "0x00618560",
            },
        },
        "level_50_big_boss_source": {
            "contract_id": "retail_big_boss_level_50_v1",
            "level_mode_id": 4,
            "lvd_sha256": facts_by_id[50]["sha256"],
            "authored_group_count": documents[50]["summary"]["active_group_count"],
            "authored_enemy_count": documents[50]["summary"]["authored_enemy_count"],
            "enemy_resources": _enemy_resources(documents[50]),
            "supplemental_spawn_records_raw_words": documents[50]["global_header"][
                "supplemental_spawn_records_raw_words"
            ],
            "tail_a_raw_words": documents[50]["unresolved_tail_array_a"]["raw_words"],
            "tail_b_raw_words": documents[50]["unresolved_tail_array_b"]["raw_words"],
            "gameplay_contract_status": "exact_state_13_trace_complete",
            "exact_trace_complete": True,
            "authoritative_contract": (
                "content/bosses.json#bosses.retail_big_boss_level_50_v1"
            ),
            "trace_entry_points": {
                "init": "0x00569260",
                "update": "0x00605fe0",
                "collision": "0x00585840",
                "mark": "0x00555c40",
                "dispatcher": "0x005afc50",
                "renderer": "0x00618560",
            },
        },
        "level_75_big_boss_source": {
            "contract_id": "retail_big_boss_level_75_v1",
            "level_mode_id": 4,
            "lvd_sha256": facts_by_id[75]["sha256"],
            "authored_group_count": documents[75]["summary"]["active_group_count"],
            "authored_enemy_count": documents[75]["summary"]["authored_enemy_count"],
            "enemy_resources": _enemy_resources(documents[75]),
            "supplemental_spawn_records_raw_words": documents[75]["global_header"][
                "supplemental_spawn_records_raw_words"
            ],
            "tail_a_raw_words": documents[75]["unresolved_tail_array_a"]["raw_words"],
            "tail_b_raw_words": documents[75]["unresolved_tail_array_b"]["raw_words"],
            "gameplay_contract_status": "exact_state_13_trace_complete",
            "exact_trace_complete": True,
            "authoritative_contract": (
                "content/bosses.json#bosses.retail_big_boss_level_75_v1"
            ),
        },
        "level_100_big_boss_source": {
            "contract_id": "retail_big_boss_level_100_v1",
            "level_mode_id": 4,
            "lvd_sha256": facts_by_id[100]["sha256"],
            "authored_group_count": documents[100]["summary"]["active_group_count"],
            "authored_enemy_count": documents[100]["summary"]["authored_enemy_count"],
            "enemy_resources": _enemy_resources(documents[100]),
            "supplemental_spawn_records_raw_words": documents[100]["global_header"][
                "supplemental_spawn_records_raw_words"
            ],
            "tail_a_raw_words": documents[100]["unresolved_tail_array_a"]["raw_words"],
            "tail_b_raw_words": documents[100]["unresolved_tail_array_b"]["raw_words"],
            "mirror_x": True,
            "gameplay_contract_status": "exact_state_13_trace_complete",
            "exact_trace_complete": True,
            "authoritative_contract": (
                "content/bosses.json#bosses.retail_big_boss_level_100_v1"
            ),
        },
        "verified_regions": regions,
    }

    outputs: dict[Path, bytes] = {
        level_content_path: _json_bytes(generated_content),
        DEFAULT_EVIDENCE: _json_bytes(evidence),
        DEFAULT_MARKDOWN: build_markdown(evidence),
    }
    for level_id, document in documents.items():
        outputs[
            DEFAULT_DECODED_DIR / f"classic_level_{level_id:03}.json"
        ] = _json_bytes(document)
    return outputs


def build_markdown(evidence: dict[str, Any]) -> bytes:
    def compact_runs(values: list[int]) -> str:
        runs: list[str] = []
        start = 0
        while start < len(values):
            end = start + 1
            while end < len(values) and values[end] == values[start]:
                end += 1
            count = end - start
            runs.append(str(values[start]) if count == 1 else f"{values[start]}×{count}")
            start = end
        return ", ".join(runs)

    lines = [
        "# Classic levels 1–100 evidence",
        "",
        "This unified inventory derives authored campaign content from the exact retail LVD bytes. The lossless documents retain the original raw blob as round-trip authority; authored v2 is the runtime projection.",
        "",
        "```sh",
        "python3 tools/classic_levels_extract.py",
        "python3 tools/classic_levels_extract.py --check",
        "```",
        "",
        "| Level | Mode | Group enemies | Authored / resolved | Paths | Resource scores | Shop |",
        "|---:|---:|---|---:|---|---|---|",
    ]
    for level in evidence["levels"]:
        resource_scores = ", ".join(
            f"{resource['raw_name']}:{resource['kill_score']}"
            for resource in level["enemy_resources"]
        )
        lines.append(
            f"| {level['level']} | {level['level_mode_id']} | "
            f"`{compact_runs(level['group_enemy_counts'])}` | "
            f"{level['authored_enemy_count']} / {level['resolved_entity_count']} | "
            f"`{compact_runs(level['path_point_counts'])}` | "
            f"`{resource_scores}` | "
            f"{'Yes' if level['shop_after'] else 'No'} |"
        )
    lines.extend(
        [
            "",
            "Every file is 117,656 bytes and reconstructs byte-identically. Resolved counts add only positive counts from supplemental records 0–3, matching the executable loop; the fifth raw record remains preserved without being treated as a spawn source.",
            "",
            "## Authored LVD v2 and fixed table",
            "",
            "Every `authored_lvd` block carries all 50 fixed records as exact four-word arrays. The retail consumers establish these semantics:",
            "",
            "- Fixed record 0 word 1 supplies ordinary-enemy animation metadata.",
            "- A supplemental spawn uses its same-index fixed record: word 0 minus one is the animation maximum and word 1 is the animation metadata/bounce flag.",
            "- Supplemental word 2 supplies health and a divisor numerator (`word2 / 10.0`); words 3 and 4 supply timer-A initial and step values.",
            "- Active supplemental entities occur on levels 3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61, 65, 69, 73, 78, 82, 86, 90, 94, and 98.",
            "",
            "Level 15 has fixed record `[7, 0, 0, 0]`, so its supplemental animation reaches frame index 6. Retail selects `(384, 0, 64, 64)`; that `alien000.hma` cell contains 1,123 occupied pixels with local inclusive bounds `[0, 0, 61, 38]`.",
            "",
            "Level 23 has supplemental record `[2, 1, 60, 1312, 29]` and fixed record `[7, 1, 0, 0]`, so two supplemental entities use all seven 64px phases with bounce metadata. The phase-6 `alien003.hma` cell contains 1,424 occupied pixels with local inclusive bounds `[2, 2, 61, 60]`.",
            "",
            "Level 28 has supplemental record `[2, 1, 30, 560, 7]` and fixed record `[4, 0, 0, 0]`, so two `alien_rakett` supplemental entities use phases 0 through 3. The phase-3 HMA cell contains 1,044 occupied pixels with local inclusive bounds `[17, 1, 46, 61]`.",
            "",
            "Level 32 has supplemental record `[3, 1, 40, 1076, 30]` and fixed record `[4, 0, 0, 0]`, so three `alien_baller` supplemental entities use phases 0 through 3. The phase-3 HMA statistics are pinned in the JSON evidence.",
            "",
            "Level 36 has two active supplemental records: `[2, 2, 40, 818, 10]` selects `alien_cyan_lilla_t` and `[1, 1, 59, 968, 14]` selects `alien_green_lilla_t`; both use four animation phases. Levels 40, 44, 48, 53, 57, and 61 retain their exact same-index resource/fixed-table linkages. Late-campaign supplementals occur at levels 65 (two records), 69, 73, 78, 82, 86, 90, 94, and 98; their fixed phase counts are source-pinned at four, seven, or six as exported under `fixed_table_contract.active_supplemental_records`.",
            "",
            "## Per-resource score table",
            "",
            "The authored resource slot is decremented into a six-case executable switch. Each case copies the corresponding LVD tail-A word to the enemy award fields; slot 2 never falls back to slot 1. The table above and `enemy_resources` arrays pin every declared resource score through level 100, including the six-slot state-13 encounters at levels 25, 50, 75, and 100.",
            "",
            "## Mode 3",
            "",
        ]
    )
    lines.extend(
        f"- {rule}" for rule in evidence["mode_3"]["proven_rules"]
    )
    lines.extend(
        [
            "",
            "Levels 8, 16, 24, 33, 41, 49, 58, 66, 74, 83, 91, and 99 are the mode-3 instances, with 20, 30, 30, 30, 40, 40, 80, 60, 84, 90, 20, and 80 authored targets respectively. Their exact resource-slot scores are retained per LVD. Result, perfect-chain, and Warp behavior remain owned by `content/bonus_modes.json#mode_three_bonus` and `BONUS_MODES.md`.",
            "",
            "## Enemy sources",
            "",
            "Levels 11–12 reuse `alien_3`; levels 13–16 use `alien000`; levels 17–20 use `alien_lilla`; levels 21–24 use `alien003`, with `alien003_3` in resource slot 2 on levels 21–23. Levels 25, 50, 75, and 100 declare the six `alien_big1`, `alien_big2`, `alien_big3`, and `alien_big4` sheets respectively. Levels 26–62 introduce the rocket, baller, lilla, raudkule, blavinger, rbille, gultop, kreps, and ving families. Levels 63–74 add royr, makk, and rocktalien families; levels 76–79 use spis; levels 80–87 use the defender and lysper families; levels 88–94 use `n1`/`n2`; and levels 95–99 use metaball, kule, and reused late families. Every campaign TGA, mask TGA, and 576×96 binary HMA is byte-pinned in `classic_levels.json` and the provenance manifest.",
            "",
            "HMA occupancy does not by itself prove broad-phase projectile rectangles. The executable HMA metadata capture and per-resource copy remain separately pinned in the presentation/runtime contract.",
            "",
            "## State-13 boss boundaries",
            "",
            "Level 25 is authored mode 4 with five groups, 16 authored entities, and six declared enemy resources. The completed state-13 initialization, update, collision, death, reward, and routing trace is exported as `content/bosses.json#bosses.retail_big_boss_v1`; `exact_trace_complete` is a fail-closed runtime gate.",
            "",
            "Level 50 is the second five-group mode-4 state-13 encounter, with 14 authored metadata records plus its dedicated supplemental boss record and all six `alien_big2` resources. Its exact contract is `content/bosses.json#bosses.retail_big_boss_level_50_v1`.",
            "",
            "Level 75 is the five-group `alien_big3` encounter and level 100 is the mirrored six-group `alien_big4` terminal encounter. Their exact contracts are `retail_big_boss_level_75_v1` and `retail_big_boss_level_100_v1` in `content/bosses.json`.",
            "",
            "Late ordinary modes include mode 6 on levels 63–65, 67–69, 71–73, 76–77, 88–90, and 92–93; mode 1 on levels 78, 80–86, 94, and 96–98; and mode 2 on levels 70, 79, 87, and 95. Late mode-3 levels are 66, 74, 83, 91, and 99; levels 75 and 100 are mode 4. Presentation uses `stars1` for 1–25, `stars2` for 26–50, `stars3` for 51–75, `stars4` for 76–99, and the retail remainder mapping `stars1` at 100. The authored every-fourth-level shop flag continues through level 100; terminal level-100 routing suppresses a reachable post-boss shop. Each mode-3 post-Warp shop remains separately owned by `bonus_modes.json#mode_three_bonus`.",
            "",
            "## Boundary",
            "",
            "The legacy `waves` arrays are predecessor-read compatibility data and are not original-game evidence. Version 9 authored play reads `authored_runtime.ordinary_speed_fp`; changing a compatibility wave cannot change an authored entity. Tail array A is named as a kill-score table only where the pinned resource-switch trace proves it; tail B remains raw. Bonus-mode results, presentation selection, and route exposure have separate owners.",
            "",
        ]
    )
    return "\n".join(lines).encode("utf-8")


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _check(path: Path, expected: bytes) -> bool:
    if not path.is_file():
        print(f"missing generated artifact: {path}", file=sys.stderr)
        return False
    if path.read_bytes() != expected:
        print(f"stale generated artifact: {path}", file=sys.stderr)
        return False
    return True


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate pinned executable/LVD evidence and authored content for "
            "classic levels 1-100."
        )
    )
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--levels-dir", type=Path, default=DEFAULT_LEVELS_DIR)
    parser.add_argument("--enemy-dir", type=Path, default=DEFAULT_ENEMY_DIR)
    parser.add_argument("--facts", type=Path, default=DEFAULT_FACTS)
    parser.add_argument("--level-content", type=Path, default=DEFAULT_LEVEL_CONTENT)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        outputs = build_outputs(
            arguments.exe.resolve(),
            arguments.levels_dir.resolve(),
            arguments.enemy_dir.resolve(),
            arguments.facts.resolve(),
            arguments.level_content.resolve(),
        )
    except (OSError, ValueError, lvd_decoder.LvdFormatError) as error:
        print(f"classic-level extraction failed: {error}", file=sys.stderr)
        return 1
    if arguments.check:
        valid = all(_check(path, payload) for path, payload in outputs.items())
        if valid:
            print("classic-level evidence and content are current")
        return 0 if valid else 1
    for path, payload in outputs.items():
        _atomic_write(path, payload)
    print(f"generated {len(outputs)} classic-level evidence/content artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3

from __future__ import annotations

import base64
import hashlib
import json
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
LEVEL_DIR = PROJECT_DIR / "assets" / "original" / "levels"
sys.path.insert(0, str(TOOLS_DIR))

import lvd_decoder
import classic_levels_extract


KNOWN_LEVEL_FACTS = {
    entry["id"]: entry
    for entry in json.loads(
        (TOOLS_DIR / "known_facts.json").read_text(encoding="utf-8")
    )["levels"]
}


EXPECTED_LEVELS = {
    1: {
        "sha256": "6938e9f31d93071b129a7c583f37751e899239bd97dd3d4c678664880d04aaf1",
        "title": "JUST WARMING UP",
        "groups": 2,
        "enemies": 18,
        "paths": [11, 11],
        "resource": "ALIEN001.bmp",
        "mode": 1,
    },
    2: {
        "sha256": "0db45277db488947b998b1478523c2e8d2905c0d720ddb9a3efc489423a38934",
        "title": "",
        "groups": 2,
        "enemies": 22,
        "paths": [10, 10],
        "resource": "ALIEN001.bmp",
        "mode": 1,
    },
    3: {
        "sha256": "32f28ba7335a5fde68951f7f4af8ecf8c6f5937cb0d12e60eafb9ee229680a33",
        "title": "THE FIRST BIG ONE",
        "groups": 2,
        "enemies": 24,
        "paths": [12, 12],
        "resource": "ALIEN001.bmp",
        "mode": 1,
    },
    4: {
        "sha256": "0c816b48f007965b14a141797603a13de900879030895016e3491a56c5ab5942",
        "title": "K A M I K A Z E",
        "groups": 25,
        "enemies": 25,
        "paths": [3] * 20 + [5] * 5,
        "resource": "ALIEN001.bmp",
        "mode": 2,
    },
    5: {
        "sha256": "0584103d5211181bb65deef633cd6d440bbc1658bcf5ed71132e740d457044c6",
        "title": "GETTING A BIT WARMER",
        "groups": 2,
        "enemies": 22,
        "paths": [21, 21],
        "resource": "ALIEN_2.bmp",
        "mode": 1,
    },
    6: {
        "sha256": "455e9317c7c88949e2a01f6bbc0a7e9d2ab123c65212ca755b285cad2c748f55",
        "title": "",
        "groups": 2,
        "enemies": 20,
        "paths": [11, 11],
        "resource": "ALIEN_2.bmp",
        "mode": 1,
    },
    7: {
        "sha256": "c8166c50a69d3b8d18a64105001b294620e7a34a9a8807aa44ab0a9c6ecb124e",
        "title": "",
        "groups": 2,
        "enemies": 28,
        "paths": [11, 11],
        "resource": "ALIEN_2.bmp",
        "mode": 1,
    },
    8: {
        "sha256": "ec06689d53be07b5b4a276892ab00798db347382e2cb42f03d2150f87ff8d743",
        "title": "* * *  B O N U S   L E V E L  * * *",
        "author": "",
        "groups": 2,
        "enemies": 20,
        "paths": [9, 9],
        "resource": "ALIEN_2.bmp",
        "mode": 3,
    },
    9: {
        "sha256": "cb74b30c90700fdbc4d99e8f0fd8f05033f33acc6d507b53a07d4e0d7c934fc7",
        "title": "",
        "groups": 2,
        "enemies": 24,
        "paths": [11, 11],
        "resource": "ALIEN_3.bmp",
        "mode": 1,
    },
    10: {
        "sha256": "9e35777eafe10d504464ee0804ea60983abfe4b8239c0e2805a529d7312b94e0",
        "title": "",
        "groups": 4,
        "enemies": 30,
        "paths": [11, 11, 11, 11],
        "resource": "ALIEN_3.bmp",
        "mode": 1,
    },
    11: {
        "sha256": "2c8dc69d4f373f3d0b4796c41045e645be7a5aa0e574d7db20f02744efddacfe",
        "title": "",
        "groups": 4,
        "enemies": 32,
        "paths": [11, 11, 11, 11],
        "resource": "ALIEN_3.bmp",
        "mode": 1,
    },
    12: {
        "sha256": "8888909c4f7a8f4bcd024d035cfbdef3ee590d075c723f5c230773049aff3a86",
        "title": "K A M I K A Z E",
        "groups": 25,
        "enemies": 25,
        "paths": [3] * 25,
        "resource": "ALIEN_3.bmp",
        "mode": 2,
    },
    13: {
        "sha256": "d8ba943e3acfe6fa21ee4177d383cbf9114de8f7b97c4de95137873afadd62b8",
        "title": "DEJA VU.....",
        "groups": 1,
        "enemies": 24,
        "paths": [16],
        "resource": "ALIEN000.bmp",
        "mode": 1,
    },
    14: {
        "sha256": "1a654e1a3ce7caefde5517ab1b661e2387977d5abd00ab36548dfb57659744a1",
        "title": "",
        "groups": 2,
        "enemies": 28,
        "paths": [16, 16],
        "resource": "ALIEN000.bmp",
        "mode": 1,
    },
    15: {
        "sha256": "1debac1fbaa5e4b2c98e2aaf6519f249ca8dd2a744a5dee24ff5e7ac5da66991",
        "title": "",
        "groups": 4,
        "enemies": 32,
        "paths": [15, 15, 15, 15],
        "resource": "ALIEN000.bmp",
        "mode": 1,
    },
    16: {
        "sha256": "21fad6d67bed291923c03fe177370e0f9f2b5777258c07ce0896f30a4b80ed12",
        "title": "* * *  B O N U S   L E V E L  * * *",
        "groups": 2,
        "enemies": 30,
        "paths": [15, 15],
        "resource": "ALIEN000.bmp",
        "mode": 3,
    },
    17: {
        "sha256": "b5f4e31dbce7ef30b1615768d35eb90b22b0ae39ce439ac108af851fc5f723a5",
        "title": "",
        "groups": 4,
        "enemies": 32,
        "paths": [14, 14, 14, 14],
        "resource": "ALIEN_Lilla.bmp",
        "mode": 1,
    },
    18: {
        "sha256": "f91d59b3f2464c5709c3056219208ab0735f045faffa00c2670d062ed4a7f1cf",
        "title": "",
        "groups": 6,
        "enemies": 34,
        "paths": [14, 14, 14, 14, 14, 14],
        "resource": "ALIEN_Lilla.bmp",
        "mode": 1,
    },
    19: {
        "sha256": "30c5e49b1486de3dd50f53a58fc0b30df0c141057e3c137fa4b1178c955079e2",
        "title": "",
        "groups": 4,
        "enemies": 28,
        "paths": [17, 17, 17, 17],
        "resource": "ALIEN_Lilla.bmp",
        "mode": 1,
    },
    20: {
        "sha256": "33dc4133c6caf4575a46c4ee56659f7eff884aa498d1ada07f81874a17e2fc62",
        "title": "K A M I K A Z E",
        "author": "",
        "groups": 6,
        "enemies": 30,
        "paths": [3, 3, 3, 3, 3, 3],
        "resource": "ALIEN_Lilla.bmp",
        "mode": 2,
    },
    21: {
        "sha256": "1188e5921436ec80804c209541b4c8d4ce22fbea8422d738a4fecb16197afd5a",
        "title": "",
        "groups": 4,
        "enemies": 32,
        "paths": [13, 13, 9, 9],
        "resource": "ALIEN003.bmp",
        "mode": 1,
    },
    22: {
        "sha256": "7caa3564e1f551b29414faa751088066bee360fb443efa686864992129716a72",
        "title": "",
        "groups": 4,
        "enemies": 30,
        "paths": [9, 9, 9, 9],
        "resource": "ALIEN003.bmp",
        "mode": 1,
    },
    23: {
        "sha256": "86ff2053ef0983bb58f3625431171d014336d168a26254257059319883ff9979",
        "title": "",
        "groups": 4,
        "enemies": 26,
        "paths": [8, 8, 7, 7],
        "resource": "ALIEN003.bmp",
        "mode": 1,
    },
    24: {
        "sha256": "d71a08ff42e78c41edb4362c3db5e74c77203c29905b0b576ebdaab9d5bcbe2e",
        "title": "* * *  B O N U S   L E V E L  * * *",
        "groups": 1,
        "enemies": 30,
        "paths": [14],
        "resource": "ALIEN003.bmp",
        "mode": 3,
    },
    25: {
        "sha256": "c8ac14a7c8a064e1904accdf8a2d763e7ff8a05210a4cdc9d197f9eba43c560c",
        "title": "* * * *   B I G  T R O U B L E  * *",
        "groups": 5,
        "enemies": 16,
        "paths": [7, 43, 0, 0, 0],
        "resource": "ALIEN_BIG1_1.bmp",
        "mode": 4,
    },
    26: {
        "sha256": "bfde5523953e9005a89685b1477939252fd63190f2aaeb92432f5d8130a4e14f",
        "title": "GOING TO THE MOON",
        "author": "",
        "groups": 1,
        "enemies": 25,
        "paths": [14],
        "resource": "ALIEN_rakett.bmp",
        "mode": 1,
    },
    27: {
        "sha256": "ee9d6f6352d6b979dbd36c8bc59c4ac15a68bda7c6cf49d1cbb4f11f1a60e83c",
        "title": "",
        "groups": 2,
        "enemies": 22,
        "paths": [14, 14],
        "resource": "ALIEN_rakett.bmp",
        "mode": 1,
    },
    28: {
        "sha256": "7124d57b5d85994898058992dc962af6d3804a6f477ca021c027163663fc0853",
        "title": "",
        "groups": 4,
        "enemies": 24,
        "paths": [17, 10, 10, 17],
        "resource": "ALIEN_rakett.bmp",
        "mode": 1,
    },
    29: {
        "sha256": "5c79d73bd15cdebc763f79c5b61d9f1deca9ae7795ea90bad28c63e65db47d89",
        "title": "K A M I K A Z E",
        "groups": 6,
        "enemies": 36,
        "paths": [3] * 6,
        "resource": "ALIEN_rakett.bmp",
        "mode": 2,
    },
    30: {
        "sha256": "7a10646f11ea7f4e287f3432abe287640de25fe860bd784a9b694442565679d7",
        "title": "",
        "groups": 4,
        "enemies": 30,
        "paths": [10, 10, 10, 10],
        "resource": "ALIEN_baller.bmp",
        "mode": 1,
    },
    31: {
        "sha256": "0bf2a4dcb3a79be4ab0ea6f78a77410dae9ab606efa24de198cb9b954f99ba19",
        "title": "",
        "author": "",
        "groups": 4,
        "enemies": 28,
        "paths": [10, 10, 10, 10],
        "resource": "ALIEN_baller.bmp",
        "mode": 1,
    },
    32: {
        "sha256": "05ce934465c2b1d676171aafeff191c0cd2008095e720502e4d85a485c810b93",
        "title": "",
        "author": "",
        "groups": 6,
        "enemies": 18,
        "paths": [10, 10, 10, 10, 10, 10],
        "resource": "ALIEN_baller.bmp",
        "mode": 1,
    },
    33: {
        "sha256": "7d411500d5f0051f808d955a83369cb2270dcdc32f6658ab9104ed408d14c839",
        "title": "* * *  B O N U S   L E V E L  * * *",
        "groups": 2,
        "enemies": 30,
        "paths": [11, 11],
        "resource": "ALIEN_baller.bmp",
        "mode": 3,
    },
    34: {
        "sha256": "a81d2fa87a458a1433dfb2f091dc2e2f6a637ede5318ea9abce1544e2a1250da",
        "title": "S Q U A R E S",
        "groups": 2,
        "enemies": 30,
        "paths": [12, 12],
        "resource": "ALIEN_Green_lilla_t.bmp",
        "mode": 1,
    },
    35: {
        "sha256": "a5a99f338362778d89b21c4a5633f3475cd2fb5d411dc0aa70cfe81d94ba85e4",
        "title": "",
        "groups": 4,
        "enemies": 36,
        "paths": [12, 12, 12, 12],
        "resource": "ALIEN_Green_lilla_t.bmp",
        "mode": 1,
    },
    36: {
        "sha256": "32c07f826ccd01339a6f7c317b9f9ce918a9d406a1a83817879100421a4015d6",
        "title": "", "author": "", "groups": 4, "enemies": 48,
        "paths": [21, 21, 21, 21], "resource": "ALIEN_Green_lilla_t.bmp", "mode": 1,
    },
    37: {
        "sha256": "773682a0039bf91617b5e47b2bedd945ff92c4d636fb54d624e0a83dd513344a",
        "title": "K A M I K A Z E", "groups": 6, "enemies": 36,
        "paths": [11, 11, 10, 10, 11, 11], "resource": "ALIEN_Green_lilla_t.bmp", "mode": 2,
    },
    38: {
        "sha256": "7538ddd7e703bac2518fa60346929dbe594cb5025beba04f92ad920f76406ee4",
        "title": "", "author": "", "groups": 2, "enemies": 36,
        "paths": [13, 13], "resource": "ALIEN_RaudKule.bmp", "mode": 1,
    },
    39: {
        "sha256": "73379105938feb131a60063efda747ace668168dfe99814628e08f2ef6a35772",
        "title": "", "groups": 2, "enemies": 40,
        "paths": [16, 16], "resource": "ALIEN_RaudKule.bmp", "mode": 1,
    },
    40: {
        "sha256": "1efa85e858c4668e0fbac60c77b65c89d3b0813fdff841cfbdcd5c14799550ed",
        "title": "", "author": "", "groups": 1, "enemies": 30,
        "paths": [15], "resource": "ALIEN_RaudKule.bmp", "mode": 1,
    },
    41: {
        "sha256": "5bc28174aa8b4aea0e7e0bd1e45cfa0ccfd9ef8b2a476da7e857a1921b8b3d82",
        "title": "* * *  B O N U S   L E V E L  * * *", "groups": 2, "enemies": 40,
        "paths": [20, 20], "resource": "ALIEN_RaudKule.bmp", "mode": 3,
    },
    42: {
        "sha256": "cb8742813e53d02135245521a9f6f954670ebaa36a567740a2078ab95024c1c9",
        "title": "", "author": "", "groups": 4, "enemies": 60,
        "paths": [9, 3, 3, 9], "resource": "ALIEN_Blavinger_gf.bmp", "mode": 1,
    },
    43: {
        "sha256": "e440b3812197ec63a880e8f38bdb986f8df84ea709ffbd08e0d4b294e24e3157",
        "title": "", "groups": 4, "enemies": 40,
        "paths": [11, 11, 11, 11], "resource": "ALIEN_Blavinger_gf.bmp", "mode": 1,
    },
    44: {
        "sha256": "0e53c0a4f98f39a14c0dbacc72afdd60eadc0cf7c8d5e2adf947948fe8ce9a60",
        "title": "", "groups": 6, "enemies": 52,
        "paths": [5, 5, 4, 4, 5, 5], "resource": "ALIEN_Blavinger_gf.bmp", "mode": 1,
    },
    45: {
        "sha256": "c2f3e865e4b0dbda6e950219f1aa50e02a81a017a7f55b58f49ea628b348d3ba",
        "title": "K A M I K A Z E", "author": "", "groups": 6, "enemies": 30,
        "paths": [3, 3, 3, 3, 3, 3], "resource": "ALIEN_Blavinger_gf2.bmp", "mode": 2,
    },
    46: {
        "sha256": "bd6b544381816314be6e900c680b4f3a42d780658b5652ac7d3c47ee765080d5",
        "title": "", "groups": 6, "enemies": 90,
        "paths": [4, 4, 5, 5, 2, 2], "resource": "ALIEN_RBille.bmp", "mode": 1,
    },
    47: {
        "sha256": "1ee7741f5a753c3b4d36efa9a37fccc46866c43ec393236a0a78f8e69fbeb321",
        "title": "", "groups": 8, "enemies": 60,
        "paths": [4, 4, 4, 4, 4, 4, 2, 2], "resource": "ALIEN_RBille.bmp", "mode": 1,
    },
    48: {
        "sha256": "2374047dc174c5b72fa151b02255253836ef8d2501a168a1ce65da31f0203775",
        "title": "", "groups": 12, "enemies": 90,
        "paths": [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 17, 17], "resource": "ALIEN_RBille.bmp", "mode": 1,
    },
    49: {
        "sha256": "5a27f4a840de7d650c0de0bb51d02a1ed990b0f66e641024a596c4846f7ce41d",
        "title": "* * *  B O N U S   L E V E L  * * *", "groups": 4, "enemies": 40,
        "paths": [4, 4, 4, 4], "resource": "ALIEN_RBille.bmp", "mode": 3,
    },
    50: {
        "sha256": "d618806d1994bd2df44371b3451c5786a727daaf4ef212da987fcc05c9619db2",
        "title": "* *   B I G  T R O U B L E   * *", "groups": 5, "enemies": 14,
        "paths": [2, 21, 0, 0, 0], "resource": "ALIEN_big2_1.bmp", "mode": 4,
    },
    51: {
        "sha256": "f0f9d2773e953b52df3839645e671754b99822e3f458ad337b1433bbc6b896b8",
        "title": "HALF CENTURIE", "author": "", "groups": 8, "enemies": 76,
        "paths": [7, 7, 7, 7, 21, 7, 7, 21], "resource": "ALIEN_gultop.bmp", "mode": 1,
    },
    52: {
        "sha256": "5f017642a15b80fb760ea47c71bcb4bc314416541c7c9523ee96492341d9b1b3",
        "title": "W O R M S", "groups": 3, "enemies": 120,
        "paths": [8, 8, 8], "resource": "ALIEN_gultop.bmp", "mode": 1,
    },
    53: {
        "sha256": "f50fd98269363d89c1f60a8c1ac74811e8f40bffd3b15d7450ea2d6a13078a48",
        "title": "", "groups": 6, "enemies": 30,
        "paths": [2, 2, 2, 2, 2, 2], "resource": "ALIEN_gultop.bmp", "mode": 1,
    },
    54: {
        "sha256": "5b45d80c0115c0d1090bd7e50aacae4574343e3d0889ad9d5230a2587d3c65cc",
        "title": "K A M I K A Z E", "groups": 6, "enemies": 36,
        "paths": [3, 3, 3, 3, 3, 3], "resource": "ALIEN_gultop.bmp", "mode": 2,
    },
    55: {
        "sha256": "e5f7dcf31adbd6120bfe111440e8f2dc7e1105f42204219b8ca052e8a24040c0",
        "title": "MORE AND MORE", "groups": 6, "enemies": 60,
        "paths": [12, 12, 12, 12, 12, 12], "resource": "ALIEN_bluekreps.bmp", "mode": 1,
    },
    56: {
        "sha256": "34b16e5b79443f6a7f26ea03f5f21c93774a863e71aa85acdf27621b1026c134",
        "title": "", "groups": 10, "enemies": 126,
        "paths": [3, 3, 4, 4, 5, 5, 5, 5, 4, 5], "resource": "ALIEN_bluekreps.bmp", "mode": 1,
    },
    57: {
        "sha256": "4075b0386414775546a162f20ed3a64e4b988e0bdbd2a88383c104f81b6c957d",
        "title": "", "groups": 8, "enemies": 110,
        "paths": [9, 9, 4, 9, 9, 4, 4, 4], "resource": "ALIEN_bluekreps.bmp", "mode": 1,
    },
    58: {
        "sha256": "dbe38e8c34e2b76e09530981df118f5354e65641d5184b59508371feebfb1717",
        "title": "* * *  B O N U S   L E V E L  * * *", "groups": 4, "enemies": 80,
        "paths": [7, 7, 7, 7], "resource": "ALIEN_brownkreps2.bmp", "mode": 3,
    },
    59: {
        "sha256": "8fe7d99f71cd836f8f73c5afe7e6eabb4710b869e95d23eabe0a6eee4a55797c",
        "title": "FIRE FLIES", "groups": 2, "enemies": 40,
        "paths": [3, 3], "resource": "ALIEN_Rvinggk.bmp", "mode": 1,
    },
    60: {
        "sha256": "09901b45fe4d24e0da9e945161c17bf45d59a9f61dd9550fd559b19dda8e52db",
        "title": "", "groups": 4, "enemies": 46,
        "paths": [5, 5, 2, 2], "resource": "ALIEN_Rvinggk.bmp", "mode": 1,
    },
    61: {
        "sha256": "2767de87ae0e6d5335d1dc2b5edc4a1d7262a83c43523a8512de63097b4132a7",
        "title": "", "groups": 1, "enemies": 22,
        "paths": [2], "resource": "ALIEN_Rvinggk.bmp", "mode": 1,
    },
    62: {
        "sha256": "ed86616a4a51717733cf52d4a19b935202afbb59eb0a4b688fe127313465cb73",
        "title": "K A M I K A Z E", "groups": 25, "enemies": 25,
        "paths": [3] * 25, "resource": "ALIEN_Gvingbk.bmp", "mode": 2,
    },
}

EXPECTED_FIXED_RECORD_0 = {
    1: [1, 0, 0, 0],
    2: [1, 0, 0, 0],
    3: [4, 1, 0, 0],
    4: [1, 0, 0, 0],
    5: [1, 0, 0, 0],
    6: [0, 0, 0, 0],
    7: [5, 0, 0, 0],
    8: [5, 0, 0, 0],
    9: [1, 0, 0, 0],
    10: [1, 0, 0, 0],
    11: [4, 1, 0, 0],
    12: [1, 0, 0, 0],
    13: [1, 0, 0, 0],
    14: [1, 0, 0, 0],
    15: [7, 0, 0, 0],
    16: [7, 0, 0, 0],
    17: [1, 0, 0, 0],
    18: [0, 0, 0, 0],
    19: [5, 1, 0, 0],
    20: [5, 0, 0, 0],
    21: [1, 0, 0, 0],
    22: [0, 0, 0, 0],
    23: [7, 1, 0, 0],
    24: [1, 0, 0, 0],
    25: [6, 0, 0, 0],
    26: [1, 0, 0, 0],
    27: [1, 0, 0, 0],
    28: [4, 0, 0, 0],
    29: [1, 0, 0, 0],
    30: [1, 0, 0, 0],
    31: [1, 0, 0, 0],
    32: [4, 0, 0, 0],
    33: [4, 0, 0, 0],
    34: [1, 0, 0, 0],
    35: [0, 0, 0, 0],
    36: [4, 1, 0, 0],
    37: [4, 1, 0, 0],
    38: [4, 1, 0, 0],
    39: [4, 1, 0, 0],
    40: [4, 0, 0, 0],
    41: [4, 0, 0, 0],
    42: [4, 0, 0, 0],
    43: [4, 0, 0, 0],
    44: [4, 1, 0, 0],
    45: [5, 0, 0, 0],
    46: [7, 0, 0, 0],
    47: [0, 0, 0, 0],
    48: [4, 1, 0, 0],
    49: [1, 0, 0, 0],
    50: [6, 0, 0, 0],
    51: [0, 0, 0, 0],
    52: [0, 0, 0, 0],
    53: [4, 0, 0, 0],
    54: [1, 0, 0, 0],
    55: [1, 0, 0, 0],
    56: [1, 0, 0, 0],
    57: [4, 1, 0, 0],
    58: [1, 0, 0, 0],
    59: [1, 0, 0, 0],
    60: [1, 0, 0, 0],
    61: [4, 1, 0, 0],
    62: [1, 0, 0, 0],
}

EXPECTED_RESOLVED_ENTITY_COUNTS = {
    1: 18,
    2: 22,
    3: 25,
    4: 25,
    5: 22,
    6: 20,
    7: 29,
    8: 20,
    9: 24,
    10: 30,
    11: 33,
    12: 25,
    13: 24,
    14: 28,
    15: 34,
    16: 30,
    17: 32,
    18: 34,
    19: 30,
    20: 30,
    21: 32,
    22: 30,
    23: 28,
    24: 30,
    25: 17,
    26: 25,
    27: 22,
    28: 26,
    29: 36,
    30: 30,
    31: 28,
    32: 21,
    33: 30,
    34: 30,
    35: 36,
    36: 51,
    37: 36,
    38: 36,
    39: 40,
    40: 34,
    41: 40,
    42: 60,
    43: 40,
    44: 56,
    45: 30,
    46: 90,
    47: 60,
    48: 94,
    49: 40,
    50: 15,
    51: 76,
    52: 120,
    53: 34,
    54: 36,
    55: 60,
    56: 126,
    57: 114,
    58: 80,
    59: 40,
    60: 46,
    61: 26,
    62: 25,
}

EXPECTED_LATE_LEVEL_SHAPES = {
    63: (6, 11, 127, [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]),
    64: (6, 9, 100, [4, 4, 4, 2, 4, 4, 4, 4, 4]),
    65: (6, 5, 75, [4, 4, 4, 6, 6]),
    66: (3, 4, 60, [3, 3, 3, 3]),
    67: (6, 8, 128, [6, 6, 6, 6, 5, 5, 5, 5]),
    68: (6, 10, 128, [4, 4, 5, 5, 5, 5, 5, 5, 5, 5]),
    69: (6, 2, 26, [2, 2]),
    70: (2, 7, 35, [3, 3, 3, 3, 3, 3, 3]),
    71: (6, 8, 78, [6, 6, 3, 3, 3, 3, 3, 3]),
    72: (6, 6, 68, [3, 3, 2, 2, 3, 3]),
    73: (6, 2, 56, [8, 8]),
    74: (3, 4, 84, [21, 21, 5, 5]),
    75: (4, 5, 20, [7, 43, 0, 1, 1]),
    76: (6, 4, 112, [20, 20, 3, 3]),
    77: (6, 6, 90, [3, 3, 3, 3, 3, 3]),
    78: (1, 4, 60, [11, 11, 11, 11]),
    79: (2, 8, 50, [4, 4, 4, 4, 4, 4, 4, 4]),
    80: (1, 10, 90, [6, 6, 5, 6, 15, 14, 6, 15, 5, 14]),
    81: (1, 10, 100, [4, 4, 4, 4, 4, 4, 4, 4, 4, 4]),
    82: (1, 2, 80, [2, 2]),
    83: (3, 6, 90, [9, 9, 9, 9, 9, 9]),
    84: (1, 7, 140, [3, 4, 2, 2, 2, 2, 4]),
    85: (1, 4, 60, [2, 2, 2, 2]),
    86: (1, 12, 96, [11, 11, 11, 11, 11, 11, 11, 11, 2, 2, 2, 2]),
    87: (2, 9, 54, [2, 2, 2, 2, 2, 2, 2, 2, 2]),
    88: (6, 3, 30, [2, 2, 2]),
    89: (6, 12, 48, [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]),
    90: (6, 8, 80, [7, 7, 7, 7, 7, 7, 7, 7]),
    91: (3, 1, 20, [24]),
    92: (6, 18, 144, [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]),
    93: (6, 8, 123, [5, 2, 5, 5, 5, 5, 5, 5]),
    94: (1, 4, 80, [13, 13, 13, 13]),
    95: (2, 10, 60, [2, 2, 2, 2, 2, 2, 2, 2, 2, 2]),
    96: (1, 6, 116, [19, 19, 10, 10, 10, 10]),
    97: (1, 2, 60, [2, 2]),
    98: (1, 3, 45, [2, 2, 2]),
    99: (3, 4, 80, [4, 4, 4, 5]),
    100: (4, 6, 12, [7, 43, 0, 2, 2, 2]),
}

EXPECTED_FIXED_RECORD_0.update({
    63: [0, 0, 0, 0], 64: [0, 0, 0, 0], 65: [4, 1, 0, 0],
    66: [1, 0, 0, 0], 67: [0, 0, 0, 0], 68: [0, 0, 0, 0],
    69: [4, 1, 0, 0], 70: [5, 0, 0, 0], 71: [0, 0, 0, 0],
    72: [1, 0, 0, 0], 73: [4, 1, 0, 0], 74: [7, 1, 0, 0],
    75: [6, 0, 0, 0], 76: [1, 0, 0, 0], 77: [1, 0, 0, 0],
    78: [4, 1, 0, 0], 79: [4, 1, 0, 0], 80: [1, 0, 0, 0],
    81: [1, 0, 0, 0], 82: [4, 1, 0, 0], 83: [1, 0, 0, 0],
    84: [1, 0, 0, 0], 85: [1, 0, 0, 0], 86: [4, 0, 0, 0],
    87: [1, 0, 0, 0], 88: [0, 0, 0, 0], 89: [1, 0, 0, 0],
    90: [7, 1, 0, 0], 91: [4, 0, 0, 0], 92: [1, 0, 0, 0],
    93: [1, 0, 0, 0], 94: [7, 1, 0, 0], 95: [1, 0, 0, 0],
    96: [0, 0, 0, 0], 97: [0, 0, 0, 0], 98: [6, 1, 0, 0],
    99: [1, 0, 0, 0], 100: [6, 1, 0, 0],
})

EXPECTED_RESOLVED_ENTITY_COUNTS.update({
    63: 127, 64: 100, 65: 79, 66: 60, 67: 128, 68: 128, 69: 30,
    70: 35, 71: 78, 72: 68, 73: 61, 74: 84, 75: 21, 76: 112,
    77: 90, 78: 64, 79: 50, 80: 90, 81: 100, 82: 85, 83: 90,
    84: 140, 85: 60, 86: 100, 87: 54, 88: 30, 89: 48, 90: 83,
    91: 20, 92: 144, 93: 123, 94: 84, 95: 60, 96: 116, 97: 60,
    98: 55, 99: 80, 100: 13,
})


class LvdLayoutTests(unittest.TestCase):
    def test_fixed_regions_are_contiguous_and_cover_the_file(self) -> None:
        regions = lvd_decoder._layout_regions()
        cursor = 0
        for region in regions:
            self.assertEqual(cursor, region["file_offset"], region["name"])
            cursor += region["size"]
        self.assertEqual(lvd_decoder.FILE_SIZE, cursor)

    def test_group_and_path_record_arithmetic(self) -> None:
        self.assertEqual(
            lvd_decoder.GROUP_SIZE,
            lvd_decoder.GROUP_HEADER_SIZE
            + lvd_decoder.ENEMY_SLOT_COUNT * lvd_decoder.ENEMY_RECORD_SIZE,
        )
        self.assertEqual(
            lvd_decoder.PATH_GROUP_SIZE,
            lvd_decoder.PATH_POINT_SLOT_COUNT * lvd_decoder.PATH_POINT_SIZE,
        )


class ClassicLevelRoundTripTests(unittest.TestCase):
    def test_all_one_hundred_levels_decode_and_round_trip_exactly(self) -> None:
        for level_number in range(1, 101):
            if level_number in EXPECTED_LEVELS:
                expected = EXPECTED_LEVELS[level_number]
            else:
                fact = KNOWN_LEVEL_FACTS[level_number]
                mode, groups, enemies, paths = EXPECTED_LATE_LEVEL_SHAPES[
                    level_number
                ]
                expected = {
                    "sha256": fact["sha256"],
                    "title": fact["title"],
                    "author": fact["author"],
                    "mode": mode,
                    "groups": groups,
                    "enemies": enemies,
                    "paths": paths,
                    "resource": fact["raw_enemy_reference"],
                }
            with self.subTest(level=level_number):
                path = LEVEL_DIR / f"classic_level_{level_number:03}.lvd"
                original = path.read_bytes()
                document = lvd_decoder.decode_blob(original, str(path))
                rebuilt = lvd_decoder.encode_document(document)

                self.assertEqual(original, rebuilt)
                self.assertEqual(
                    expected["sha256"], hashlib.sha256(rebuilt).hexdigest()
                )
                self.assertEqual(
                    original,
                    base64.b64decode(document["raw_blob_base64"], validate=True),
                )
                self.assertEqual(expected["title"], document["summary"]["title"])
                self.assertEqual(
                    expected.get("author", "EDGAR VIGDAL"),
                    document["summary"]["author"],
                )
                self.assertEqual(
                    expected["mode"], document["summary"]["level_mode_id"]
                )
                self.assertEqual(
                    expected["groups"], document["summary"]["active_group_count"]
                )
                self.assertEqual(
                    expected["enemies"], document["summary"]["authored_enemy_count"]
                )
                self.assertEqual(
                    expected["paths"],
                    [
                        group["active_path_point_count"]
                        for group in document["active_groups"]
                    ],
                )
                self.assertEqual(
                    expected["resource"],
                    document["resource_slots"][0]["text_cp1252"],
                )
                self.assertIn(
                    "global compacted 14-file SWD catalog",
                    document["summary"]["swd_reference_status"],
                )
                self.assertEqual(
                    "evidence_only",
                    document["field_contract"]["fields"]["path_unknown_0c"][
                        "confidence"
                    ],
                )
                fixed_records = document["unresolved_fixed_table"]["records"]
                self.assertEqual(50, len(fixed_records))
                self.assertTrue(
                    all(len(record["raw_words"]) == 4 for record in fixed_records)
                )
                self.assertEqual(
                    EXPECTED_FIXED_RECORD_0[level_number],
                    fixed_records[0]["raw_words"],
                )
                supplemental = document["global_header"][
                    "supplemental_spawn_records_raw_words"
                ]
                self.assertEqual(
                    EXPECTED_RESOLVED_ENTITY_COUNTS[level_number],
                    document["summary"]["authored_enemy_count"]
                    + sum(max(0, record[0]) for record in supplemental[:4]),
                )

    def test_active_enemy_raw_records_have_exact_offsets(self) -> None:
        path = LEVEL_DIR / "classic_level_001.lvd"
        document = lvd_decoder.decode_file(path)
        first_group = document["active_groups"][0]
        first_enemy = first_group["enemies"][0]
        second_enemy = first_group["enemies"][1]
        self.assertEqual(
            lvd_decoder.GROUP_OFFSET + lvd_decoder.GROUP_HEADER_SIZE,
            first_enemy["file_offset"],
        )
        self.assertEqual(
            first_enemy["file_offset"] + lvd_decoder.ENEMY_RECORD_SIZE,
            second_enemy["file_offset"],
        )
        self.assertEqual(
            [-42, 85, 1, 1, 2400, 100, 2400, 100],
            first_enemy["raw_words"],
        )

    def test_level_one_mirrored_entry_origins(self) -> None:
        document = lvd_decoder.decode_file(
            LEVEL_DIR / "classic_level_001.lvd"
        )
        origins = [
            (group["entry_origin_x"], group["entry_origin_y"])
            for group in document["active_groups"]
        ]
        self.assertEqual([(-200, -75), (202, -73)], origins)

    def test_runtime_contract_matches_traced_fixed_tick_rules(self) -> None:
        document = lvd_decoder.decode_file(
            LEVEL_DIR / "classic_level_004.lvd"
        )
        contract = document["runtime_contract"]
        self.assertEqual(800, contract["logical_width"])
        self.assertEqual(1, contract["normal_fixed_tick_scale"])
        self.assertEqual(
            {0, 6},
            {
                point["opcode"]
                for group in document["active_groups"]
                for point in group["path_points"]
            },
        )

    def test_authored_v2_carries_exact_fixed_tables(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        self.assertEqual(10, content["version"])
        self.assertEqual("warblade.levels.v10", content["schema"])
        self.assertEqual(
            list(range(1, 101)),
            [level["id"] for level in content["levels"]],
        )
        self.assertEqual(
            list(range(4, 101, 4)),
            [level["id"] for level in content["levels"] if level["shop_after"]],
        )
        for level in content["levels"]:
            with self.subTest(level=level["id"]):
                authored = level["authored_lvd"]
                self.assertEqual("warblade.lvd.authored.v2", authored["schema"])
                fixed = authored["fixed_table_records_raw_words"]
                self.assertEqual(50, len(fixed))
                self.assertTrue(all(len(record) == 4 for record in fixed))
                self.assertEqual(EXPECTED_FIXED_RECORD_0[level["id"]], fixed[0])
                source = lvd_decoder.decode_file(
                    LEVEL_DIR / f"classic_level_{level['id']:03}.lvd"
                )
                self.assertEqual(
                    [
                        record["raw_words"]
                        for record in source["unresolved_fixed_table"]["records"]
                    ],
                    fixed,
                )
                self.assertEqual(
                    {"ordinary_speed_fp": 65536}, level["authored_runtime"]
                )
                self.assertEqual(
                    "predecessor_compatibility",
                    level["waves"][0]["content_status"],
                )

    def test_mixed_resource_scores_are_ordered_and_slot_specific(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        expected_mixed = [
            {
                "resource_slot_id": 1,
                "raw_name": "ALIEN003.bmp",
                "enemy_sheet_id": "alien003",
                "kill_score": 200,
            },
            {
                "resource_slot_id": 2,
                "raw_name": "ALIEN003_3.bmp",
                "enemy_sheet_id": "alien003_3",
                "kill_score": 300,
            },
        ]
        for level_id in (21, 22, 23):
            level = content["levels"][level_id - 1]
            self.assertEqual(expected_mixed, level["enemy_resources"])
            self.assertEqual("alien003", level["enemy_sprite"])
            self.assertEqual(200, level["ordinary_kill_score"])
            self.assertNotEqual(
                level["enemy_resources"][0]["kill_score"],
                level["enemy_resources"][1]["kill_score"],
            )
        level_25 = content["levels"][24]
        self.assertEqual(list(range(1, 7)), [
            resource["resource_slot_id"]
            for resource in level_25["enemy_resources"]
        ])
        self.assertEqual(
            [50, 50, 0, 0, 0, 0],
            [resource["kill_score"] for resource in level_25["enemy_resources"]],
        )
        expected_rocket_scores = {
            26: [300, 400],
            27: [300, 400],
            28: [300, 400],
            29: [400, 400],
        }
        for level_id, scores in expected_rocket_scores.items():
            level = content["levels"][level_id - 1]
            self.assertEqual(
                ["alien_rakett", "alien_rakett_gronn"],
                [resource["enemy_sheet_id"] for resource in level["enemy_resources"]],
            )
            self.assertEqual(
                scores,
                [resource["kill_score"] for resource in level["enemy_resources"]],
            )
        for level_id in (30, 31, 32, 33):
            level = content["levels"][level_id - 1]
            self.assertEqual(
                ["alien_baller", "alien_baller2"],
                [resource["enemy_sheet_id"] for resource in level["enemy_resources"]],
            )
            self.assertEqual(
                [500, 600],
                [resource["kill_score"] for resource in level["enemy_resources"]],
            )
        for level_id in (34, 35):
            level = content["levels"][level_id - 1]
            self.assertEqual(
                ["alien_green_lilla_t", "alien_cyan_lilla_t"],
                [resource["enemy_sheet_id"] for resource in level["enemy_resources"]],
            )
            self.assertEqual(
                [450, 550],
                [resource["kill_score"] for resource in level["enemy_resources"]],
            )
        expected_late_resources = {
            36: (["alien_green_lilla_t", "alien_cyan_lilla_t"], [450, 550]),
            37: (["alien_green_lilla_t", "alien_cyan_lilla_t"], [450, 550]),
            38: (["alien_raudkule", "alien_cyan_lilla_t"], [500, 550]),
            39: (["alien_raudkule", "alien_raudkule2"], [500, 550]),
            40: (["alien_raudkule", "alien_raudkule2"], [500, 550]),
            41: (["alien_raudkule", "alien_raudkule2"], [500, 550]),
            42: (["alien_blavinger_gf", "alien_raudkule2"], [600, 550]),
            43: (["alien_blavinger_gf", "alien_raudkule2"], [600, 550]),
            44: (["alien_blavinger_gf", "alien_blavinger_gf2"], [600, 750]),
            45: (["alien_blavinger_gf2"], [200]),
            46: (["alien_rbille"], [800]),
            47: (["alien_rbille"], [850]),
            48: (["alien_rbille"], [850]),
            49: (["alien_rbille"], [750]),
            50: ([
                "alien_big2_1", "alien_big2_2", "alien_big2_3",
                "alien_big2_4", "alien_big2_5", "alien_big2_6",
            ], [0, 0, 0, 0, 0, 0]),
            51: (["alien_gultop"], [1000]),
            52: (["alien_gultop"], [1000]),
            53: (["alien_gultop", "alien_lillatop"], [1000, 1200]),
            54: (["alien_gultop", "alien_rakett_gronn"], [500, 400]),
            55: (["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"], [750, 800, 1000]),
            56: (["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"], [750, 800, 1000]),
            57: (["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"], [750, 800, 1000]),
            58: (["alien_brownkreps2", "alien_gulkreps"], [500, 500]),
            59: (["alien_rvinggk", "alien_rvinggk"], [750, 750]),
            60: (["alien_rvinggk", "alien_gvingbk"], [750, 750]),
            61: (["alien_rvinggk", "alien_gvingbk"], [750, 750]),
            62: (["alien_gvingbk"], [500]),
        }
        for level_id, (sheet_ids, scores) in expected_late_resources.items():
            level = content["levels"][level_id - 1]
            self.assertEqual(
                sheet_ids,
                [resource["enemy_sheet_id"] for resource in level["enemy_resources"]],
            )
            self.assertEqual(
                scores,
                [resource["kill_score"] for resource in level["enemy_resources"]],
            )
        for level in content["levels"][62:]:
            self.assertEqual(
                KNOWN_LEVEL_FACTS[level["id"]]["enemy_resources"],
                level["enemy_resources"],
                f"level {level['id']} resource catalog drift",
            )

    def test_levels_sixty_three_through_one_hundred_special_cases_are_exact(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        levels = content["levels"]
        self.assertEqual(
            [63, 64, 65, 67, 68, 69, 71, 72, 73, 76, 77, 88, 89, 90, 92, 93],
            [
                level["id"]
                for level in levels[62:]
                if level["authored_lvd"]["level_mode_id"] == 6
            ],
        )
        level_75 = levels[74]["authored_lvd"]
        self.assertEqual([4, 5, 6, 7, 7], [g["group_mode_id"] for g in level_75["groups"]])
        self.assertEqual([1, 1, 613, 904, 10], level_75["supplemental_spawn_records_raw_words"][0])
        self.assertEqual([6, 0, 0, 0], level_75["fixed_table_records_raw_words"][0])
        self.assertEqual([[3], [3]], [[p["opcode"] for p in g["path_points"]] for g in level_75["groups"][3:]])

        level_100 = levels[99]["authored_lvd"]
        self.assertTrue(level_100["mirror_x"])
        self.assertEqual([4, 5, 6, 6, 7, 7], [g["group_mode_id"] for g in level_100["groups"]])
        self.assertEqual([1, 1, 500, 904, 10], level_100["supplemental_spawn_records_raw_words"][0])
        self.assertEqual([6, 1, 0, 0], level_100["fixed_table_records_raw_words"][0])
        self.assertEqual(
            [[6, 1], [6, 1], [6, 1]],
            [[p["opcode"] for p in g["path_points"]] for g in level_100["groups"][3:]],
        )

        level_80 = levels[79]["authored_lvd"]
        self.assertEqual(
            [3, 3, 1, 1, 1, 1, 1, 1, 1, 1],
            [group["group_mode_id"] for group in level_80["groups"]],
        )
        level_94_opcodes = [
            [point["opcode"] for point in group["path_points"]]
            for group in levels[93]["authored_lvd"]["groups"]
        ]
        self.assertEqual(
            [
                [6, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 1],
                [6, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 1],
                [0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 1],
                [0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 1],
            ],
            level_94_opcodes,
        )

    def test_level_twenty_eight_has_two_four_phase_supplementals(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        authored = content["levels"][27]["authored_lvd"]
        self.assertEqual(
            [2, 1, 30, 560, 7],
            authored["supplemental_spawn_records_raw_words"][0],
        )
        self.assertEqual([4, 0, 0, 0], authored["fixed_table_records_raw_words"][0])

    def test_level_thirty_two_has_three_four_phase_supplementals(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        authored = content["levels"][31]["authored_lvd"]
        self.assertEqual(
            [3, 1, 40, 1076, 30],
            authored["supplemental_spawn_records_raw_words"][0],
        )
        self.assertEqual([4, 0, 0, 0], authored["fixed_table_records_raw_words"][0])

    def test_level_thirty_three_splits_targets_and_scores_by_resource(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        level = content["levels"][32]
        counts = {1: 0, 2: 0}
        for group in level["authored_lvd"]["groups"]:
            for enemy in group["enemies"]:
                counts[enemy["resource_slot_id"]] += 1
        self.assertEqual({1: 15, 2: 15}, counts)
        self.assertEqual([500, 600], [
            resource["kill_score"] for resource in level["enemy_resources"]
        ])

    def test_level_thirty_six_has_two_four_phase_supplemental_records(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        authored = content["levels"][35]["authored_lvd"]
        self.assertEqual(
            [[2, 2, 40, 818, 10], [1, 1, 59, 968, 14]],
            authored["supplemental_spawn_records_raw_words"][:2],
        )
        self.assertEqual(
            [[4, 1, 0, 0], [4, 1, 0, 0]],
            authored["fixed_table_records_raw_words"][:2],
        )

    def test_late_supplemental_and_mode_three_boundaries_are_exact(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        expected_supplemental = {
            40: ([4, 1, 40, 818, 10], [4, 0, 0, 0]),
            44: ([4, 2, 79, 968, 19], [4, 1, 0, 0]),
            48: ([4, 1, 50, 1054, 13], [4, 1, 0, 0]),
        }
        for level_id, (record, fixed) in expected_supplemental.items():
            authored = content["levels"][level_id - 1]["authored_lvd"]
            self.assertEqual(record, authored["supplemental_spawn_records_raw_words"][0])
            self.assertEqual(fixed, authored["fixed_table_records_raw_words"][0])
        for level_id, target_count in ((41, 40), (49, 40), (58, 80)):
            level = content["levels"][level_id - 1]
            self.assertEqual(3, level["authored_lvd"]["level_mode_id"])
            self.assertEqual(
                target_count,
                sum(len(group["enemies"]) for group in level["authored_lvd"]["groups"]),
            )

    def test_levels_fifty_one_through_sixty_two_stay_within_supported_contracts(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        late_levels = content["levels"][50:62]
        self.assertEqual({1, 2, 3}, {
            level["authored_lvd"]["level_mode_id"] for level in late_levels
        })
        self.assertEqual(
            {0, 1, 6},
            {
                point["opcode"]
                for level in late_levels
                for group in level["authored_lvd"]["groups"]
                for point in group["path_points"]
            },
        )
        expected_supplemental = {
            53: [
                ([2, 1, 59, 925, 8], [4, 0, 0, 0]),
                ([2, 1, 79, 1054, 22], [4, 0, 0, 0]),
            ],
            57: [([4, 3, 98, 1441, 7], [4, 1, 0, 0])],
            61: [([4, 1, 88, 1162, 23], [4, 1, 0, 0])],
        }
        for level_id, records in expected_supplemental.items():
            authored = content["levels"][level_id - 1]["authored_lvd"]
            for record_index, (raw_words, fixed_words) in enumerate(records):
                self.assertEqual(
                    raw_words,
                    authored["supplemental_spawn_records_raw_words"][record_index],
                )
                self.assertEqual(
                    fixed_words,
                    authored["fixed_table_records_raw_words"][record_index],
                )

    def test_level_fifty_state_thirteen_source_is_exact(self) -> None:
        content = json.loads(classic_levels_extract.DEFAULT_LEVEL_CONTENT.read_text())
        level = content["levels"][49]
        authored = level["authored_lvd"]
        self.assertEqual(50, level["id"])
        self.assertEqual(4, authored["level_mode_id"])
        self.assertEqual([4, 5, 6, 7, 7], [
            group["group_mode_id"] for group in authored["groups"]
        ])
        self.assertEqual(
            [1, 1, 500, 1377, 8],
            authored["supplemental_spawn_records_raw_words"][0],
        )
        self.assertEqual([6, 0, 0, 0], authored["fixed_table_records_raw_words"][0])

    def test_classic_level_generated_artifacts_are_current(self) -> None:
        outputs = classic_levels_extract.build_outputs(
            classic_levels_extract.DEFAULT_EXE.resolve(),
            classic_levels_extract.DEFAULT_LEVELS_DIR.resolve(),
            classic_levels_extract.DEFAULT_ENEMY_DIR.resolve(),
            classic_levels_extract.DEFAULT_FACTS.resolve(),
            classic_levels_extract.DEFAULT_LEVEL_CONTENT.resolve(),
        )
        for path, expected in outputs.items():
            with self.subTest(path=path):
                self.assertTrue(path.is_file())
                self.assertEqual(expected, path.read_bytes())
        markdown = classic_levels_extract.DEFAULT_MARKDOWN.read_text(encoding="utf-8")
        self.assertIn("# Classic levels 1–100 evidence", markdown)
        self.assertIn("levels 75 and 100 are mode 4", markdown)
        self.assertNotIn("Classic levels 1–62 evidence", markdown)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""生成 curated/zh_dishes_snacks.json —— 中式熟食/餐饮/零食/饮料补充库。

背景：cfct（成分表）+ USDA 覆盖原料与包装制品，但「一碗牛肉面」「一杯奶茶」
「一份宫保鸡丁」这类**熟食/餐饮 SKU** 是记录高频缺口（真机走查 + 搜索抽查
确认：奶茶/披萨/烧卖/虾饺/辣条/宫保鸡丁 全部 0 命中）。

营养口径：每 100g 可食部，估值来源 = 《中国食物成分表》同类菜品推算 +
USDA 快餐条目交叉参考；kcal 一律按 Atwater 4P+4C+9F 反算（熟食无酒精/高纤维
场景，与标示值口径一致）。〔假设〕待营养侧校对（同 zh_common_foods 口径）。

元组：(zh, en, aliases_zh, aliases_en, protein_g, carb_g, fat_g, category)
  - aliases 不含正名本身（build 校验 E3 只要求非空）；
  - 避免与 cfct 现有条目重名（油条/豆浆/方便面/火腿肠/酸奶/鸡胸肉等不重复放）。
"""
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE.parent
OUT = DATA_DIR / "curated" / "zh_dishes_snacks.json"

# (中文, 英文, 中文别名, 英文别名, 蛋白, 碳水, 脂肪, 分类)
ROWS: list[tuple[str, str, list[str], list[str], float, float, float, str]] = [
    # ── 早点 / 早茶（粤式饮茶 + 国民早点）──────────────────────────────
    ("小笼包", "Xiaolongbao (Steamed Soup Dumpling)", ["小笼汤包", "灌汤包"], ["soup dumpling", "xiaolongbao"], 9.0, 26.0, 7.0, "早点"),
    ("生煎包", "Shengjian Bao (Pan-fried Bun)", ["生煎馒头"], ["pan-fried bun", "shengjian"], 10.0, 28.0, 8.5, "早点"),
    ("叉烧包", "BBQ Pork Bun (Char Siu Bao)", ["叉烧包(蒸)"], ["char siu bun", "bbq pork bun"], 8.0, 30.0, 8.0, "早点"),
    ("流沙包", "Lava Custard Bun", ["奶黄包", "爆浆奶黄包"], ["lava custard bun", "custard bun"], 6.0, 35.0, 13.0, "早点"),
    ("虾饺", "Har Gow (Shrimp Dumpling)", ["水晶虾饺", "虾饺皇"], ["har gow", "shrimp dumpling"], 9.5, 20.0, 4.5, "早点"),
    ("烧卖", "Siu Mai (Pork Shrimp Dumpling)", ["烧麦", "干蒸烧卖"], ["siu mai", "shumai"], 9.0, 22.0, 7.0, "早点"),
    ("糯米鸡", "Lotus Leaf Sticky Rice Chicken", ["荷叶糯米鸡"], ["lotus leaf rice", "sticky rice chicken"], 9.0, 32.0, 8.0, "早点"),
    ("肠粉", "Rice Roll (Cheung Fun)", ["布拉肠", "抽屉肠粉"], ["rice roll", "cheung fun"], 4.0, 20.0, 3.5, "早点"),
    ("虾仁肠粉", "Shrimp Rice Roll", ["鲜虾肠粉"], ["shrimp rice roll"], 6.5, 20.0, 4.0, "早点"),
    ("凤爪", "Steamed Chicken Feet (Dim Sum)", ["豉汁凤爪", "虎皮凤爪"], ["steamed chicken feet", "dim sum feet"], 18.0, 5.0, 14.0, "早点"),
    ("萝卜糕", "Steamed Radish Cake", ["广式萝卜糕"], ["radish cake", "turnip cake"], 3.0, 17.0, 10.0, "早点"),
    ("芋头糕", "Steamed Taro Cake", ["广式芋头糕"], ["taro cake"], 4.0, 19.0, 10.0, "早点"),
    ("马拉糕", "Malga Sponge Cake", ["蒸马拉糕"], ["malga cake", "steamed sponge cake"], 5.0, 40.0, 12.0, "早点"),
    ("蛋挞", "Egg Tart", ["葡式蛋挞", "酥皮蛋挞"], ["egg tart", "pastel de nata"], 6.5, 30.0, 25.0, "早点"),
    ("牛肉球", "Steamed Beef Ball", ["陈皮牛肉球"], ["steamed beef ball"], 14.0, 10.0, 8.0, "早点"),
    ("皮蛋瘦肉粥", "Century Egg Pork Congee", ["皮蛋粥", "瘦肉粥"], ["century egg congee", "pork congee"], 3.5, 8.5, 1.4, "早点"),
    ("艇仔粥", "Sampan Congee", ["广东艇仔粥"], ["sampan congee"], 3.0, 8.0, 1.2, "早点"),
    ("小米粥", "Millet Congee", ["小米饭粥"], ["millet congee", "millet porridge"], 1.4, 9.5, 0.7, "早点"),
    ("南瓜粥", "Pumpkin Congee", ["大米南瓜粥"], ["pumpkin congee", "pumpkin porridge"], 1.0, 9.5, 0.4, "早点"),
    ("白粥", "Plain Rice Congee", ["白饭粥", "大米粥"], ["plain congee", "rice porridge"], 0.9, 9.0, 0.2, "早点"),
    ("茶叶蛋", "Tea-marinated Egg", ["五香茶叶蛋", "卤蛋"], ["tea egg", "marinated egg"], 12.5, 2.0, 10.5, "早点"),
    ("豆腐脑", "Tofu Pudding (Savory)", ["豆腐花", "豆花"], ["tofu pudding", "douhua"], 5.0, 2.5, 2.0, "早点"),
    ("葱油饼", "Scallion Pancake", ["葱油烙饼"], ["scallion pancake"], 6.0, 42.0, 18.0, "早点"),
    ("麻团", "Sesame Ball (Jian Dui)", ["煎堆", "芝麻球"], ["sesame ball", "jian dui"], 6.0, 48.0, 20.0, "早点"),
    ("糖油饼", "Sweet Fried Dough Cake", ["糖饼"], ["sweet fried dough"], 6.5, 48.0, 17.0, "早点"),
    ("烧饼", "Baked Sesame Flatbread", ["芝麻烧饼", "火烧"], ["sesame flatbread", "shaobing"], 8.5, 52.0, 9.0, "早点"),
    ("煎饼果子", "Jianbing (Chinese Crepe)", ["煎饼", "杂粮煎饼"], ["jianbing", "chinese crepe"], 8.0, 32.0, 10.0, "早点"),
    ("鸡蛋灌饼", "Egg-stuffed Pancake", ["灌饼"], ["egg stuffed pancake"], 8.5, 33.0, 11.0, "早点"),
    ("肉夹馍", "Roujiamo (Chinese Burger)", ["腊汁肉夹馍"], ["roujiamo", "chinese burger"], 10.0, 33.0, 11.0, "早点"),
    ("胡辣汤", "Spicy Pepper Soup (Hulatang)", ["河南胡辣汤"], ["hulatang", "spicy soup"], 3.5, 9.0, 3.0, "早点"),
    ("水饺", "Boiled Dumpling (Jiaozi)", ["饺子", "猪肉水饺", "水饺(猪肉白菜)"], ["boiled dumpling", "jiaozi"], 10.5, 24.0, 9.0, "早点"),
    ("蒸饺", "Steamed Dumpling", ["蒸饺(猪肉)"], ["steamed dumpling"], 10.0, 26.0, 7.5, "早点"),
    ("馄饨", "Wonton Soup", ["云吞", "抄手"], ["wonton", "wonton soup"], 6.0, 14.0, 4.0, "早点"),
    ("锅贴", "Pan-fried Dumpling", ["牛肉锅贴", "猪肉锅贴"], ["potsticker", "pan-fried dumpling"], 10.0, 24.0, 10.5, "早点"),
    ("油饼", "Fried Flatbread", ["炸油饼"], ["fried flatbread"], 7.5, 44.0, 15.0, "早点"),

    # ── 零食 / 坚果 ──────────────────────────────────────────────────
    ("薯片", "Potato Chips", ["土豆片", "洋芋片"], ["potato chips", "crisps"], 4.0, 53.0, 35.0, "零食"),
    ("虾条", "Prawn Crackers", ["虾片"], ["prawn crackers", "shrimp snack"], 5.0, 65.0, 25.0, "零食"),
    ("辣条", "Spicy Gluten Snack (Latiao)", ["大面筋", "调味面制品"], ["latiao", "spicy gluten"], 12.0, 30.0, 16.0, "零食"),
    ("锅巴", "Rice Crust Snack", ["糯米锅巴"], ["rice crust snack"], 7.0, 62.0, 22.0, "零食"),
    ("苏打饼干", "Soda Cracker", ["梳打饼"], ["soda cracker"], 8.0, 62.0, 14.0, "零食"),
    ("夹心饼干", "Sandwich Cookie", ["奥利奥", "巧克力夹心饼干"], ["sandwich cookie", "oreo"], 5.5, 65.0, 22.0, "零食"),
    ("威化饼干", "Wafer Biscuit", ["威化饼"], ["wafer"], 6.0, 60.0, 28.0, "零食"),
    ("曲奇", "Butter Cookie", ["黄油曲奇", "巧克力曲奇"], ["cookie", "butter cookie"], 6.5, 58.0, 26.0, "零食"),
    ("沙琪玛", "Sachima", ["沙其玛"], ["sachima"], 7.0, 58.0, 24.0, "零食"),
    ("桃酥", "Walnut Cookie (Taosu)", ["核桃酥"], ["chinese walnut cookie"], 7.0, 60.0, 27.0, "零食"),
    ("月饼", "Mooncake", ["莲蓉月饼", "蛋黄月饼"], ["mooncake"], 8.0, 55.0, 19.0, "零食"),
    ("粽子", "Zongzi (Sticky Rice Dumpling)", ["肉粽", "豆沙粽"], ["zongzi", "rice dumpling"], 6.0, 38.0, 4.5, "零食"),
    ("汤圆", "Tangyuan (Glutinous Rice Ball)", ["元宵", "芝麻汤圆"], ["tangyuan", "glutinous rice ball"], 5.0, 40.0, 9.0, "零食"),
    ("黑巧克力", "Dark Chocolate", ["黑巧", "可可含量70%巧克力"], ["dark chocolate"], 8.0, 45.0, 40.0, "零食"),
    ("牛奶巧克力", "Milk Chocolate", ["奶巧", "牛奶巧克力排"], ["milk chocolate"], 7.5, 55.0, 30.0, "零食"),
    ("硬糖", "Hard Candy", ["水果硬糖"], ["hard candy"], 0.0, 95.0, 0.0, "零食"),
    ("棉花糖", "Marshmallow", ["马什马洛"], ["marshmallow"], 1.5, 80.0, 0.2, "零食"),
    ("冰淇淋", "Ice Cream", ["香草冰淇淋", "冰激凌"], ["ice cream"], 3.5, 23.0, 11.0, "零食"),
    ("雪糕", "Ice Pop / Bar", ["冰棍", "棒冰"], ["ice pop", "ice bar"], 2.5, 26.0, 6.0, "零食"),
    ("双皮奶", "Double-skin Milk Pudding", ["广东双皮奶"], ["double skin milk"], 6.5, 17.0, 8.0, "零食"),
    ("龟苓膏", "Guilinggao (Herbal Jelly)", ["龟苓膏(原味)"], ["herbal jelly", "guilinggao"], 1.0, 12.0, 0.2, "零食"),
    ("果冻", "Fruit Jelly", ["果冻条"], ["fruit jelly"], 0.5, 15.0, 0.1, "零食"),
    ("奶油爆米花", "Butter Popcorn", ["焦糖爆米花"], ["butter popcorn"], 7.0, 65.0, 18.0, "零食"),
    ("瓜子", "Sunflower Seeds (Roasted)", ["葵花籽", "瓜子(炒)"], ["sunflower seeds"], 22.0, 20.0, 50.0, "零食"),
    ("炒花生", "Roasted Peanuts", ["花生米", "油炸花生"], ["roasted peanuts"], 25.0, 16.0, 48.0, "零食"),
    ("腰果", "Cashew Nuts", ["腰果仁"], ["cashew"], 18.0, 30.0, 46.0, "零食"),
    ("杏仁", "Almonds", ["巴旦木", "扁桃仁"], ["almond"], 21.0, 22.0, 54.0, "零食"),
    ("核桃仁", "Walnut Kernel", ["核桃肉"], ["walnut"], 15.0, 14.0, 65.0, "零食"),
    ("每日坚果", "Daily Mixed Nuts", ["混合坚果", "坚果包"], ["mixed nuts pack"], 17.0, 22.0, 47.0, "零食"),
    ("碧根果", "Pecan", ["长寿果"], ["pecan"], 9.0, 14.0, 70.0, "零食"),
    ("开心果", "Pistachio", ["开心果(炒)"], ["pistachio"], 20.0, 28.0, 50.0, "零食"),
    ("夏威夷果", "Macadamia", ["澳洲坚果"], ["macadamia"], 8.0, 14.0, 76.0, "零食"),
    ("牛肉干", "Beef Jerky", ["风干牛肉", "牛肉脯"], ["beef jerky"], 45.0, 12.0, 8.0, "零食"),
    ("猪肉脯", "Pork Jerky", ["肉脯", "靖江猪肉脯"], ["pork jerky"], 30.0, 25.0, 15.0, "零食"),
    ("鱿鱼丝", "Dried Squid Snack", ["手撕鱿鱼"], ["dried squid snack"], 35.0, 15.0, 3.0, "零食"),
    ("海苔", "Nori / Seaweed Snack", ["紫菜零食", "烤海苔"], ["seaweed snack", "nori"], 25.0, 40.0, 5.0, "零食"),
    ("豆腐干", "Dried Tofu Snack", ["豆干", "五香豆干"], ["dried tofu snack"], 16.0, 8.0, 8.0, "零食"),
    ("卤鸡爪", "Braised Chicken Feet", ["凤爪(卤)", "泡椒凤爪"], ["braised chicken feet"], 20.0, 5.0, 13.0, "零食"),
    ("鸭脖", "Spicy Duck Neck", ["卤鸭脖", "麻辣鸭脖"], ["spicy duck neck"], 19.0, 6.0, 12.0, "零食"),
    ("蛋卷", "Egg Roll Biscuit", ["手工蛋卷"], ["egg roll biscuit"], 8.0, 55.0, 25.0, "零食"),
    ("米饼", "Rice Cracker", ["雪饼"], ["rice cracker"], 6.0, 78.0, 12.0, "零食"),

    # ── 饮料 / 咖啡 / 酒 ─────────────────────────────────────────────
    ("可乐", "Cola", ["碳酸饮料", "汽水"], ["cola", "soft drink"], 0.0, 10.6, 0.0, "饮料"),
    ("雪碧", "Sprite (Lemon-lime Soda)", ["柠檬汽水"], ["lemon lime soda"], 0.0, 10.2, 0.0, "饮料"),
    ("橙味汽水", "Orange Soda", ["芬达"], ["orange soda", "fanta"], 0.0, 11.0, 0.0, "饮料"),
    ("珍珠奶茶", "Bubble Tea (Milk Tea with Pearls)", ["奶茶", "波霸奶茶", "珍珠"], ["bubble tea", "boba milk tea"], 1.5, 12.0, 2.8, "饮料"),
    ("奶茶(无糖)", "Milk Tea (Unsweetened)", ["无糖奶茶", "鲜奶茶"], ["unsweetened milk tea"], 2.0, 6.0, 2.5, "饮料"),
    ("美式咖啡", "Americano", ["黑咖啡", "美式"], ["americano", "black coffee"], 0.2, 0.2, 0.1, "饮料"),
    ("拿铁咖啡", "Latte", ["拿铁", "咖啡拿铁"], ["latte"], 3.0, 5.0, 2.8, "饮料"),
    ("卡布奇诺", "Cappuccino", ["卡布"], ["cappuccino"], 3.2, 5.5, 3.5, "饮料"),
    ("摩卡咖啡", "Mocha", ["摩卡"], ["mocha"], 3.5, 10.0, 4.5, "饮料"),
    ("速溶咖啡(含糖)", "Instant Coffee (with Sugar)", ["三合一咖啡"], ["3-in-1 instant coffee"], 2.5, 70.0, 8.0, "饮料"),
    ("鲜榨橙汁", "Fresh Orange Juice", ["橙汁"], ["orange juice"], 0.8, 10.5, 0.2, "饮料"),
    ("椰子水", "Coconut Water", ["椰青水"], ["coconut water"], 0.7, 4.0, 0.2, "饮料"),
    ("椰汁", "Coconut Milk Drink", ["椰奶饮料"], ["coconut drink"], 1.0, 8.0, 2.5, "饮料"),
    ("杏仁露", "Almond Milk Drink", ["露露杏仁露"], ["almond drink"], 1.2, 9.0, 2.2, "饮料"),
    ("豆奶", "Soy Milk Drink", ["豆乳饮料"], ["soy milk drink"], 3.0, 6.5, 1.8, "饮料"),
    ("酸梅汤", "Sour Plum Drink (Suanmeitang)", ["乌梅汤"], ["sour plum drink"], 0.5, 10.0, 0.1, "饮料"),
    ("柠檬茶", "Lemon Tea", ["冻柠茶"], ["lemon tea"], 0.1, 8.0, 0.0, "饮料"),
    ("凉茶", "Herbal Tea (Cooling)", ["王老吉", "加多宝"], ["herbal cooling tea"], 0.0, 8.0, 0.0, "饮料"),
    ("运动饮料", "Sports Drink", ["电解质饮料"], ["sports drink", "electrolyte drink"], 0.1, 6.0, 0.0, "饮料"),
    ("气泡水", "Sparkling Water", ["苏打气泡水", "无糖气泡水"], ["sparkling water"], 0.0, 0.0, 0.0, "饮料"),
    ("酸奶饮品", "Yogurt Drink", ["乳酸菌饮料", "养乐多"], ["yogurt drink", "lactic drink"], 1.0, 12.0, 0.5, "饮料"),
    ("茶", "Tea (Brewed)", ["绿茶", "红茶", "茶水"], ["brewed tea"], 0.0, 0.0, 0.0, "饮料"),
    ("啤酒", "Beer", ["拉格", "精酿啤酒"], ["beer"], 0.4, 3.5, 0.0, "饮料"),
    ("红酒", "Red Wine", ["干红葡萄酒"], ["red wine"], 0.1, 2.5, 0.0, "饮料"),
    ("白酒", "Baijiu (Chinese Liquor)", ["二锅头", "高粱酒"], ["baijiu"], 0.2, 0.0, 0.0, "饮料"),
    ("米酒", "Rice Wine", ["醪糟", "酒酿"], ["rice wine", "jiuniang"], 1.5, 8.0, 0.2, "饮料"),

    # ── 轻食 / 西餐 ──────────────────────────────────────────────────
    ("蔬菜沙拉", "Garden Salad", ["田园沙拉", "生菜沙拉"], ["garden salad"], 1.8, 4.0, 2.5, "轻食"),
    ("凯撒沙拉", "Caesar Salad", ["凯撒鸡胸沙拉"], ["caesar salad"], 6.0, 6.0, 9.0, "轻食"),
    ("金枪鱼沙拉", "Tuna Salad", ["吞拿鱼沙拉"], ["tuna salad"], 12.0, 5.0, 9.0, "轻食"),
    ("土豆沙拉", "Potato Salad", ["马铃薯沙拉"], ["potato salad"], 3.0, 14.0, 6.0, "轻食"),
    ("鸡胸沙拉", "Chicken Breast Salad", ["鸡肉沙拉碗"], ["chicken salad"], 14.0, 6.0, 5.0, "轻食"),
    ("金枪鱼三明治", "Tuna Sandwich", ["吞拿鱼三明治"], ["tuna sandwich"], 10.0, 25.0, 7.0, "轻食"),
    ("鸡蛋三明治", "Egg Sandwich", ["蛋沙拉三明治"], ["egg sandwich"], 8.5, 24.0, 7.0, "轻食"),
    ("全麦三明治", "Whole Wheat Sandwich", ["全麦夹心"], ["whole wheat sandwich"], 9.0, 26.0, 5.5, "轻食"),
    ("汉堡", "Beef Burger", ["牛肉汉堡", "芝士汉堡"], ["beef burger", "cheeseburger"], 15.0, 24.0, 13.0, "轻食"),
    ("鸡腿堡", "Chicken Burger", ["香辣鸡腿堡", "炸鸡堡"], ["chicken burger", "fillet burger"], 14.0, 26.0, 14.0, "轻食"),
    ("玛格丽特披萨", "Margherita Pizza", ["披萨", "芝士披萨"], ["margherita pizza"], 11.0, 31.0, 10.0, "轻食"),
    ("超级披萨", "Supreme Pizza", ["什锦披萨", "肉披萨"], ["supreme pizza"], 12.0, 29.0, 12.0, "轻食"),
    ("肉酱意面", "Spaghetti Bolognese", ["意大利面", "番茄肉酱面"], ["spaghetti bolognese"], 9.0, 24.0, 5.0, "轻食"),
    ("奶油意面", "Alfredo Pasta", ["白酱意面", "奶油培根面"], ["alfredo pasta"], 8.0, 23.0, 9.0, "轻食"),
    ("煎西冷牛排", "Pan-seared Sirloin Steak", ["牛排", "西冷"], ["sirloin steak"], 26.0, 0.0, 13.0, "轻食"),
    ("三文鱼寿司", "Salmon Nigiri", ["三文鱼握寿司", "寿司"], ["salmon nigiri", "sushi"], 12.0, 22.0, 3.5, "轻食"),
    ("加州卷", "California Roll", ["寿司卷"], ["california roll"], 9.0, 25.0, 3.0, "轻食"),
    ("波奇饭", "Poke Bowl", ["夏威夷盖饭", "三文鱼波奇"], ["poke bowl"], 9.0, 22.0, 4.0, "轻食"),
    ("藜麦饭", "Quinoa Bowl", ["藜麦碗"], ["quinoa bowl"], 4.5, 21.0, 1.8, "轻食"),
    ("牛油果吐司", "Avocado Toast", ["酪梨吐司"], ["avocado toast"], 5.0, 22.0, 11.0, "轻食"),
    ("能量棒", "Energy Bar", ["谷物棒"], ["energy bar"], 8.0, 50.0, 14.0, "轻食"),
    ("蛋白棒", "Protein Bar", ["蛋白质棒"], ["protein bar"], 20.0, 40.0, 9.0, "轻食"),
    ("薯条", "French Fries", ["炸薯条"], ["french fries"], 3.5, 42.0, 15.0, "轻食"),
    ("鸡块", "Chicken Nuggets", ["麦乐鸡", "上校鸡块"], ["chicken nuggets"], 13.0, 18.0, 15.0, "轻食"),
    ("奶油蘑菇汤", "Cream of Mushroom Soup", ["蘑菇浓汤"], ["mushroom soup"], 2.5, 6.0, 7.0, "轻食"),
    ("玉米浓汤", "Corn Chowder", ["玉米奶油汤"], ["corn chowder"], 3.0, 10.0, 5.0, "轻食"),
    ("罗宋汤", "Borscht", ["红菜汤"], ["borscht"], 1.5, 7.0, 2.0, "轻食"),
    ("可颂", "Croissant", ["牛角包", "羊角面包"], ["croissant"], 8.0, 40.0, 24.0, "轻食"),
    ("贝果", "Bagel", ["贝果面包"], ["bagel"], 10.0, 48.0, 1.5, "轻食"),
    ("法棍", "Baguette", ["法式长棍"], ["baguette"], 9.0, 48.0, 1.0, "轻食"),
    ("松饼", "Pancake", ["班戟", "美式松饼"], ["pancake"], 6.0, 38.0, 7.0, "轻食"),
    ("华夫饼", "Waffle", ["窝夫"], ["waffle"], 6.5, 45.0, 17.0, "轻食"),
    ("甜甜圈", "Donut", ["冬甩", "多拿滋"], ["donut", "doughnut"], 5.0, 48.0, 23.0, "轻食"),
    ("提拉米苏", "Tiramisu", ["提拉米苏蛋糕"], ["tiramisu"], 6.0, 28.0, 18.0, "轻食"),
    ("芝士蛋糕", "Cheesecake", ["奶酪蛋糕"], ["cheesecake"], 7.0, 25.0, 22.0, "轻食"),
    ("慕斯蛋糕", "Mousse Cake", ["巧克力慕斯"], ["mousse cake"], 5.0, 28.0, 20.0, "轻食"),
    ("千层面", "Lasagna", ["意大利千层"], ["lasagna"], 10.0, 18.0, 10.0, "轻食"),
    ("焗饭", "Baked Rice Gratin", ["芝士焗饭"], ["baked rice gratin"], 8.0, 24.0, 9.0, "轻食"),
    ("德式香肠", "German Sausage", ["烤肠", "香肠(西式)"], ["bratwurst", "german sausage"], 12.0, 2.0, 27.0, "轻食"),
    ("培根", "Bacon", ["烟肉"], ["bacon"], 12.0, 1.0, 42.0, "轻食"),
    ("土豆泥", "Mashed Potato", ["马铃薯泥"], ["mashed potato"], 2.4, 14.0, 4.0, "轻食"),
    ("热狗", "Hot Dog", ["热狗面包"], ["hot dog"], 10.0, 24.0, 13.0, "轻食"),

    # ── 中餐熟食 / 家常菜（成品菜）───────────────────────────────────
    ("蛋炒饭", "Egg Fried Rice", ["炒饭"], ["egg fried rice"], 5.5, 25.0, 6.5, "中餐"),
    ("扬州炒饭", "Yangzhou Fried Rice", ["虾仁炒饭"], ["yangzhou fried rice"], 6.5, 24.0, 6.5, "中餐"),
    ("咖喱鸡肉饭", "Chicken Curry Rice", ["咖喱饭"], ["chicken curry rice"], 7.0, 24.0, 6.0, "中餐"),
    ("卤肉饭", "Braised Pork Rice", ["肉燥饭"], ["braised pork rice"], 6.0, 24.0, 7.5, "中餐"),
    ("盖浇饭", "Rice with Topped Stir-fry", ["盖饭"], ["rice with stir-fry topping"], 5.5, 24.0, 5.5, "中餐"),
    ("黄焖鸡米饭", "Braised Chicken Rice (Huangmenji)", ["黄焖鸡"], ["braised chicken rice"], 9.0, 22.0, 7.0, "中餐"),
    ("宫保鸡丁", "Kung Pao Chicken", ["宫爆鸡丁"], ["kung pao chicken"], 14.0, 10.0, 9.0, "中餐"),
    ("鱼香肉丝", "Yu Sheng Shredded Pork", ["鱼香肉丝(川菜)"], ["fish-fragrant shredded pork"], 12.0, 12.0, 8.0, "中餐"),
    ("麻婆豆腐", "Mapo Tofu", ["麻婆豆腐(川菜)"], ["mapo tofu"], 8.0, 6.0, 9.0, "中餐"),
    ("西红柿炒鸡蛋", "Stir-fried Tomato and Egg", ["番茄炒蛋", "番茄炒鸡蛋"], ["tomato egg stir-fry"], 6.0, 5.0, 7.0, "中餐"),
    ("青椒肉丝", "Shredded Pork with Green Pepper", ["辣椒炒肉丝"], ["shredded pork with pepper"], 13.0, 8.0, 9.0, "中餐"),
    ("地三鲜", "Stir-fried Eggplant Potato Pepper", ["地三鲜(东北)"], ["di san xian"], 2.0, 12.0, 9.0, "中餐"),
    ("酸辣土豆丝", "Shredded Potato Hot-sour Stir-fry", ["土豆丝"], ["shredded potato"], 2.0, 12.0, 4.0, "中餐"),
    ("干煸四季豆", "Dry-fried Green Beans", ["干煸豆角"], ["dry-fried green beans"], 3.0, 9.0, 8.0, "中餐"),
    ("红烧肉", "Braised Pork Belly (Hongshaorou)", ["东坡肉", "焖肉"], ["braised pork belly"], 13.0, 8.0, 37.0, "中餐"),
    ("糖醋里脊", "Sweet and Sour Pork", ["咕咾肉", "咕噜肉"], ["sweet and sour pork"], 12.0, 22.0, 9.0, "中餐"),
    ("梅菜扣肉", "Steamed Pork with Preserved Vegetables", ["扣肉"], ["steamed pork with meicai"], 12.0, 8.0, 30.0, "中餐"),
    ("回锅肉", "Twice-cooked Pork", ["回锅肉(川菜)"], ["twice cooked pork"], 12.0, 6.0, 25.0, "中餐"),
    ("红烧排骨", "Braised Spare Ribs", ["糖醋排骨"], ["braised spare ribs"], 16.0, 9.0, 20.0, "中餐"),
    ("可乐鸡翅", "Cola Chicken Wings", ["可乐鸡中翅"], ["cola chicken wings"], 16.0, 9.0, 12.0, "中餐"),
    ("辣子鸡", "Chongqing Spicy Chicken", ["重庆辣子鸡"], ["spicy diced chicken"], 20.0, 8.0, 16.0, "中餐"),
    ("水煮鱼", "Poached Fish in Chili Oil", ["水煮肉片"], ["poached fish chili oil"], 14.0, 4.0, 13.0, "中餐"),
    ("酸菜鱼", "Fish with Pickled Cabbage", ["老坛酸菜鱼"], ["pickled cabbage fish"], 12.0, 4.0, 9.0, "中餐"),
    ("毛血旺", "Mao Xue Wang (Spicy Blood Curd)", ["血旺"], ["mao xue wang"], 8.0, 5.0, 11.0, "中餐"),
    ("清蒸鲈鱼", "Steamed Sea Bass", ["清蒸鱼"], ["steamed sea bass"], 19.0, 1.0, 4.5, "中餐"),
    ("烤羊肉串", "Lamb Skewer", ["羊肉串"], ["lamb skewer"], 20.0, 4.0, 13.0, "中餐"),
    ("铁板豆腐", "Iron-plate Tofu", ["铁板日本豆腐"], ["iron plate tofu"], 8.0, 6.0, 8.0, "中餐"),
    ("牛肉面", "Beef Noodle Soup", ["红烧牛肉面", "牛肉拉面"], ["beef noodle soup"], 6.5, 20.0, 3.5, "中餐"),
    ("炸酱面", "Zhajiang Noodles", ["老北京炸酱面"], ["zhajiang noodles"], 7.0, 25.0, 5.0, "中餐"),
    ("热干面", "Hot Dry Noodles (Wuhan)", ["武汉热干面"], ["hot dry noodles"], 8.0, 28.0, 7.0, "中餐"),
    ("重庆小面", "Chongqing Noodles", ["麻辣小面"], ["chongqing noodles"], 6.0, 24.0, 6.0, "中餐"),
    ("番茄鸡蛋面", "Tomato Egg Noodle Soup", ["西红柿鸡蛋面"], ["tomato egg noodle"], 5.0, 22.0, 3.0, "中餐"),
    ("米线", "Rice Noodle Soup", ["云南米线", "过桥米线"], ["rice noodles"], 3.0, 22.0, 2.0, "中餐"),
    ("螺蛳粉", "Liuzhou Snail Rice Noodles", ["柳州螺蛳粉"], ["luosifen", "snail noodles"], 5.0, 22.0, 4.0, "中餐"),
    ("酸辣粉", "Hot and Sour Glass Noodles", ["重庆酸辣粉"], ["hot sour glass noodles"], 3.0, 24.0, 4.0, "中餐"),
    ("麻辣烫", "Spicy Hot Pot (Mala Tang)", ["串签麻辣烫"], ["mala tang"], 6.0, 8.0, 6.0, "中餐"),
    ("冒菜", "Maocai (Sichuan Spicy Pot)", ["成都冒菜"], ["maocai"], 7.0, 8.0, 7.0, "中餐"),
    ("火锅肥牛", "Hot Pot Beef Slices", ["肥牛卷", "涮肥牛"], ["hot pot beef"], 15.0, 2.0, 18.0, "中餐"),
    ("烤冷面", "Grilled Cold Noodles", ["东北烤冷面"], ["grilled cold noodles"], 8.0, 30.0, 7.0, "中餐"),
    ("铁锅炖鱼", "Iron-pot Stewed Fish", ["东北铁锅炖"], ["iron pot stewed fish"], 13.0, 5.0, 9.0, "中餐"),
    ("炖排骨汤", "Pork Rib Soup", ["排骨汤", "玉米排骨汤"], ["pork rib soup"], 8.0, 3.0, 9.0, "中餐"),
    ("鸡汤", "Chicken Soup", ["老母鸡汤"], ["chicken soup"], 6.0, 2.0, 5.0, "中餐"),
    ("蛋花汤", "Egg Drop Soup", ["番茄蛋花汤"], ["egg drop soup"], 2.5, 3.0, 2.0, "中餐"),
    ("紫菜蛋花汤", "Seaweed Egg Soup", ["紫菜汤"], ["seaweed egg soup"], 2.5, 3.0, 1.8, "中餐"),
    ("白切鸡", "Poached Chicken (Bai Qie Ji)", ["白斩鸡"], ["poached chicken"], 20.0, 1.0, 9.0, "中餐"),
    ("蜜汁叉烧", "Honey BBQ Pork (Char Siu)", ["叉烧", "蜜汁叉烧肉"], ["char siu"], 20.0, 12.0, 10.0, "中餐"),
    ("北京烤鸭", "Peking Duck", ["烤鸭"], ["peking duck"], 19.0, 5.0, 22.0, "中餐"),
    ("小龙虾", "Crayfish (Spicy)", ["麻辣小龙虾", "十三香小龙虾"], ["crayfish"], 18.0, 2.0, 8.0, "中餐"),
    ("蒜蓉粉丝虾", "Steamed Shrimp with Garlic Vermicelli", ["粉丝蒸虾"], ["garlic shrimp vermicelli"], 15.0, 8.0, 3.0, "中餐"),
    ("剁椒鱼头", "Fish Head with Chopped Chili", ["剁椒鱼头(湘菜)"], ["chopped chili fish head"], 15.0, 3.0, 9.0, "中餐"),
]


def main() -> int:
    # 入库去重：正名与既有 seed 行（zh_common 策展 + cfct 成分表）精确同名 →
    # 丢弃新行（旧行优先保留——已随旧 seed 出厂）。搜「面条」出两行不同值才是事故。
    taken: set[str] = set()
    for src in (
        DATA_DIR / "curated" / "zh_common_foods.json",
        DATA_DIR / "cfct" / "cfct_foods.json",
    ):
        if src.exists():
            for f in json.loads(src.read_text(encoding="utf-8"))["foods"]:
                if f.get("name_zh"):
                    taken.add(f["name_zh"])

    foods = []
    seen = set()
    dropped: list[str] = []
    for zh, en, azh, aen, p, c, f, cat in ROWS:
        if zh in taken:
            dropped.append(zh)
            continue
        slug = en_slug(en)
        assert slug not in seen, f"duplicate slug: {slug}"
        seen.add(slug)
        kcal = round(4 * p + 4 * c + 9 * f, 1)
        foods.append(
            {
                "id": f"curated-{slug}",
                "name_zh": zh,
                "name_en": en,
                "aliases_zh": azh,
                "aliases_en": aen,
                "kcal": kcal,
                "protein_g": p,
                "carb_g": c,
                "fat_g": f,
                "category": cat,
                "source": "curated",
                "zh_verified": True,
            }
        )
    if dropped:
        print(f"[dishes] 同名去重丢弃 {len(dropped)} 行（既有行优先）: {dropped}")

    OUT.write_text(
        json.dumps(
            {
                "_meta": {
                    "source": "curated",
                    "note": "中式熟食/餐饮/零食/饮料补充库：每100g 可食部，kcal 按 "
                            "Atwater 4P+4C+9F 反算〔假设〕（成分表/USDA 交叉参考），"
                            "待营养侧校对。生成器 scripts/gen_dishes_snacks.py。",
                },
                "foods": foods,
            },
            ensure_ascii=False,
            indent=1,
        ),
        encoding="utf-8",
    )
    print(f"[dishes] {len(foods)} entries -> {OUT}")
    return 0


def en_slug(en: str) -> str:
    """英文稳定 slug：小写、非字母数字转连字符（与 curated 既有 id 口径一致）。"""
    out = []
    for ch in en.lower():
        out.append(ch if ch.isalnum() else "-")
    return "-".join(s for s in "".join(out).split("-") if s)


if __name__ == "__main__":
    raise SystemExit(main())

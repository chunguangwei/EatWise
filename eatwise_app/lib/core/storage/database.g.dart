// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FoodsTable extends Foods with TableInfo<$FoodsTable, Food> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameZhMeta = const VerificationMeta('nameZh');
  @override
  late final GeneratedColumn<String> nameZh = GeneratedColumn<String>(
    'name_zh',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameEnMeta = const VerificationMeta('nameEn');
  @override
  late final GeneratedColumn<String> nameEn = GeneratedColumn<String>(
    'name_en',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasesZhMeta = const VerificationMeta(
    'aliasesZh',
  );
  @override
  late final GeneratedColumn<String> aliasesZh = GeneratedColumn<String>(
    'aliases_zh',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _aliasesEnMeta = const VerificationMeta(
    'aliasesEn',
  );
  @override
  late final GeneratedColumn<String> aliasesEn = GeneratedColumn<String>(
    'aliases_en',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _kcalPer100gMeta = const VerificationMeta(
    'kcalPer100g',
  );
  @override
  late final GeneratedColumn<double> kcalPer100g = GeneratedColumn<double>(
    'kcal_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinPer100gMeta = const VerificationMeta(
    'proteinPer100g',
  );
  @override
  late final GeneratedColumn<double> proteinPer100g = GeneratedColumn<double>(
    'protein_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbPer100gMeta = const VerificationMeta(
    'carbPer100g',
  );
  @override
  late final GeneratedColumn<double> carbPer100g = GeneratedColumn<double>(
    'carb_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fatPer100gMeta = const VerificationMeta(
    'fatPer100g',
  );
  @override
  late final GeneratedColumn<double> fatPer100g = GeneratedColumn<double>(
    'fat_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nameZh,
    nameEn,
    aliasesZh,
    aliasesEn,
    kcalPer100g,
    proteinPer100g,
    carbPer100g,
    fatPer100g,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'foods';
  @override
  VerificationContext validateIntegrity(
    Insertable<Food> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name_zh')) {
      context.handle(
        _nameZhMeta,
        nameZh.isAcceptableOrUnknown(data['name_zh']!, _nameZhMeta),
      );
    } else if (isInserting) {
      context.missing(_nameZhMeta);
    }
    if (data.containsKey('name_en')) {
      context.handle(
        _nameEnMeta,
        nameEn.isAcceptableOrUnknown(data['name_en']!, _nameEnMeta),
      );
    } else if (isInserting) {
      context.missing(_nameEnMeta);
    }
    if (data.containsKey('aliases_zh')) {
      context.handle(
        _aliasesZhMeta,
        aliasesZh.isAcceptableOrUnknown(data['aliases_zh']!, _aliasesZhMeta),
      );
    }
    if (data.containsKey('aliases_en')) {
      context.handle(
        _aliasesEnMeta,
        aliasesEn.isAcceptableOrUnknown(data['aliases_en']!, _aliasesEnMeta),
      );
    }
    if (data.containsKey('kcal_per100g')) {
      context.handle(
        _kcalPer100gMeta,
        kcalPer100g.isAcceptableOrUnknown(
          data['kcal_per100g']!,
          _kcalPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_kcalPer100gMeta);
    }
    if (data.containsKey('protein_per100g')) {
      context.handle(
        _proteinPer100gMeta,
        proteinPer100g.isAcceptableOrUnknown(
          data['protein_per100g']!,
          _proteinPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_proteinPer100gMeta);
    }
    if (data.containsKey('carb_per100g')) {
      context.handle(
        _carbPer100gMeta,
        carbPer100g.isAcceptableOrUnknown(
          data['carb_per100g']!,
          _carbPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_carbPer100gMeta);
    }
    if (data.containsKey('fat_per100g')) {
      context.handle(
        _fatPer100gMeta,
        fatPer100g.isAcceptableOrUnknown(data['fat_per100g']!, _fatPer100gMeta),
      );
    } else if (isInserting) {
      context.missing(_fatPer100gMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Food map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Food(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      nameZh: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_zh'],
      )!,
      nameEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_en'],
      )!,
      aliasesZh: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases_zh'],
      )!,
      aliasesEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases_en'],
      )!,
      kcalPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal_per100g'],
      )!,
      proteinPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_per100g'],
      )!,
      carbPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_per100g'],
      )!,
      fatPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_per100g'],
      )!,
    );
  }

  @override
  $FoodsTable createAlias(String alias) {
    return $FoodsTable(attachedDatabase, alias);
  }
}

class Food extends DataClass implements Insertable<Food> {
  /// 食物条目 ID。
  final String id;

  /// 中文名（D-15）。
  final String nameZh;

  /// 英文名（D-15）。
  final String nameEn;

  /// 中文别名（JSON 字符串数组，LIKE 搜索直接匹配）。
  final String aliasesZh;

  /// 英文别名（JSON 字符串数组）。
  final String aliasesEn;

  /// 每 100g 热量（kcal）。
  final double kcalPer100g;

  /// 每 100g 蛋白质（g）。
  final double proteinPer100g;

  /// 每 100g 碳水（g）。
  final double carbPer100g;

  /// 每 100g 脂肪（g）。
  final double fatPer100g;
  const Food({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.aliasesZh,
    required this.aliasesEn,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbPer100g,
    required this.fatPer100g,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name_zh'] = Variable<String>(nameZh);
    map['name_en'] = Variable<String>(nameEn);
    map['aliases_zh'] = Variable<String>(aliasesZh);
    map['aliases_en'] = Variable<String>(aliasesEn);
    map['kcal_per100g'] = Variable<double>(kcalPer100g);
    map['protein_per100g'] = Variable<double>(proteinPer100g);
    map['carb_per100g'] = Variable<double>(carbPer100g);
    map['fat_per100g'] = Variable<double>(fatPer100g);
    return map;
  }

  FoodsCompanion toCompanion(bool nullToAbsent) {
    return FoodsCompanion(
      id: Value(id),
      nameZh: Value(nameZh),
      nameEn: Value(nameEn),
      aliasesZh: Value(aliasesZh),
      aliasesEn: Value(aliasesEn),
      kcalPer100g: Value(kcalPer100g),
      proteinPer100g: Value(proteinPer100g),
      carbPer100g: Value(carbPer100g),
      fatPer100g: Value(fatPer100g),
    );
  }

  factory Food.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Food(
      id: serializer.fromJson<String>(json['id']),
      nameZh: serializer.fromJson<String>(json['nameZh']),
      nameEn: serializer.fromJson<String>(json['nameEn']),
      aliasesZh: serializer.fromJson<String>(json['aliasesZh']),
      aliasesEn: serializer.fromJson<String>(json['aliasesEn']),
      kcalPer100g: serializer.fromJson<double>(json['kcalPer100g']),
      proteinPer100g: serializer.fromJson<double>(json['proteinPer100g']),
      carbPer100g: serializer.fromJson<double>(json['carbPer100g']),
      fatPer100g: serializer.fromJson<double>(json['fatPer100g']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nameZh': serializer.toJson<String>(nameZh),
      'nameEn': serializer.toJson<String>(nameEn),
      'aliasesZh': serializer.toJson<String>(aliasesZh),
      'aliasesEn': serializer.toJson<String>(aliasesEn),
      'kcalPer100g': serializer.toJson<double>(kcalPer100g),
      'proteinPer100g': serializer.toJson<double>(proteinPer100g),
      'carbPer100g': serializer.toJson<double>(carbPer100g),
      'fatPer100g': serializer.toJson<double>(fatPer100g),
    };
  }

  Food copyWith({
    String? id,
    String? nameZh,
    String? nameEn,
    String? aliasesZh,
    String? aliasesEn,
    double? kcalPer100g,
    double? proteinPer100g,
    double? carbPer100g,
    double? fatPer100g,
  }) => Food(
    id: id ?? this.id,
    nameZh: nameZh ?? this.nameZh,
    nameEn: nameEn ?? this.nameEn,
    aliasesZh: aliasesZh ?? this.aliasesZh,
    aliasesEn: aliasesEn ?? this.aliasesEn,
    kcalPer100g: kcalPer100g ?? this.kcalPer100g,
    proteinPer100g: proteinPer100g ?? this.proteinPer100g,
    carbPer100g: carbPer100g ?? this.carbPer100g,
    fatPer100g: fatPer100g ?? this.fatPer100g,
  );
  Food copyWithCompanion(FoodsCompanion data) {
    return Food(
      id: data.id.present ? data.id.value : this.id,
      nameZh: data.nameZh.present ? data.nameZh.value : this.nameZh,
      nameEn: data.nameEn.present ? data.nameEn.value : this.nameEn,
      aliasesZh: data.aliasesZh.present ? data.aliasesZh.value : this.aliasesZh,
      aliasesEn: data.aliasesEn.present ? data.aliasesEn.value : this.aliasesEn,
      kcalPer100g: data.kcalPer100g.present
          ? data.kcalPer100g.value
          : this.kcalPer100g,
      proteinPer100g: data.proteinPer100g.present
          ? data.proteinPer100g.value
          : this.proteinPer100g,
      carbPer100g: data.carbPer100g.present
          ? data.carbPer100g.value
          : this.carbPer100g,
      fatPer100g: data.fatPer100g.present
          ? data.fatPer100g.value
          : this.fatPer100g,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Food(')
          ..write('id: $id, ')
          ..write('nameZh: $nameZh, ')
          ..write('nameEn: $nameEn, ')
          ..write('aliasesZh: $aliasesZh, ')
          ..write('aliasesEn: $aliasesEn, ')
          ..write('kcalPer100g: $kcalPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('carbPer100g: $carbPer100g, ')
          ..write('fatPer100g: $fatPer100g')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    nameZh,
    nameEn,
    aliasesZh,
    aliasesEn,
    kcalPer100g,
    proteinPer100g,
    carbPer100g,
    fatPer100g,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Food &&
          other.id == this.id &&
          other.nameZh == this.nameZh &&
          other.nameEn == this.nameEn &&
          other.aliasesZh == this.aliasesZh &&
          other.aliasesEn == this.aliasesEn &&
          other.kcalPer100g == this.kcalPer100g &&
          other.proteinPer100g == this.proteinPer100g &&
          other.carbPer100g == this.carbPer100g &&
          other.fatPer100g == this.fatPer100g);
}

class FoodsCompanion extends UpdateCompanion<Food> {
  final Value<String> id;
  final Value<String> nameZh;
  final Value<String> nameEn;
  final Value<String> aliasesZh;
  final Value<String> aliasesEn;
  final Value<double> kcalPer100g;
  final Value<double> proteinPer100g;
  final Value<double> carbPer100g;
  final Value<double> fatPer100g;
  final Value<int> rowid;
  const FoodsCompanion({
    this.id = const Value.absent(),
    this.nameZh = const Value.absent(),
    this.nameEn = const Value.absent(),
    this.aliasesZh = const Value.absent(),
    this.aliasesEn = const Value.absent(),
    this.kcalPer100g = const Value.absent(),
    this.proteinPer100g = const Value.absent(),
    this.carbPer100g = const Value.absent(),
    this.fatPer100g = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodsCompanion.insert({
    required String id,
    required String nameZh,
    required String nameEn,
    this.aliasesZh = const Value.absent(),
    this.aliasesEn = const Value.absent(),
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbPer100g,
    required double fatPer100g,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       nameZh = Value(nameZh),
       nameEn = Value(nameEn),
       kcalPer100g = Value(kcalPer100g),
       proteinPer100g = Value(proteinPer100g),
       carbPer100g = Value(carbPer100g),
       fatPer100g = Value(fatPer100g);
  static Insertable<Food> custom({
    Expression<String>? id,
    Expression<String>? nameZh,
    Expression<String>? nameEn,
    Expression<String>? aliasesZh,
    Expression<String>? aliasesEn,
    Expression<double>? kcalPer100g,
    Expression<double>? proteinPer100g,
    Expression<double>? carbPer100g,
    Expression<double>? fatPer100g,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nameZh != null) 'name_zh': nameZh,
      if (nameEn != null) 'name_en': nameEn,
      if (aliasesZh != null) 'aliases_zh': aliasesZh,
      if (aliasesEn != null) 'aliases_en': aliasesEn,
      if (kcalPer100g != null) 'kcal_per100g': kcalPer100g,
      if (proteinPer100g != null) 'protein_per100g': proteinPer100g,
      if (carbPer100g != null) 'carb_per100g': carbPer100g,
      if (fatPer100g != null) 'fat_per100g': fatPer100g,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodsCompanion copyWith({
    Value<String>? id,
    Value<String>? nameZh,
    Value<String>? nameEn,
    Value<String>? aliasesZh,
    Value<String>? aliasesEn,
    Value<double>? kcalPer100g,
    Value<double>? proteinPer100g,
    Value<double>? carbPer100g,
    Value<double>? fatPer100g,
    Value<int>? rowid,
  }) {
    return FoodsCompanion(
      id: id ?? this.id,
      nameZh: nameZh ?? this.nameZh,
      nameEn: nameEn ?? this.nameEn,
      aliasesZh: aliasesZh ?? this.aliasesZh,
      aliasesEn: aliasesEn ?? this.aliasesEn,
      kcalPer100g: kcalPer100g ?? this.kcalPer100g,
      proteinPer100g: proteinPer100g ?? this.proteinPer100g,
      carbPer100g: carbPer100g ?? this.carbPer100g,
      fatPer100g: fatPer100g ?? this.fatPer100g,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nameZh.present) {
      map['name_zh'] = Variable<String>(nameZh.value);
    }
    if (nameEn.present) {
      map['name_en'] = Variable<String>(nameEn.value);
    }
    if (aliasesZh.present) {
      map['aliases_zh'] = Variable<String>(aliasesZh.value);
    }
    if (aliasesEn.present) {
      map['aliases_en'] = Variable<String>(aliasesEn.value);
    }
    if (kcalPer100g.present) {
      map['kcal_per100g'] = Variable<double>(kcalPer100g.value);
    }
    if (proteinPer100g.present) {
      map['protein_per100g'] = Variable<double>(proteinPer100g.value);
    }
    if (carbPer100g.present) {
      map['carb_per100g'] = Variable<double>(carbPer100g.value);
    }
    if (fatPer100g.present) {
      map['fat_per100g'] = Variable<double>(fatPer100g.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodsCompanion(')
          ..write('id: $id, ')
          ..write('nameZh: $nameZh, ')
          ..write('nameEn: $nameEn, ')
          ..write('aliasesZh: $aliasesZh, ')
          ..write('aliasesEn: $aliasesEn, ')
          ..write('kcalPer100g: $kcalPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('carbPer100g: $carbPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodEntriesTable extends FoodEntries
    with TableInfo<$FoodEntriesTable, FoodEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientRequestIdMeta = const VerificationMeta(
    'clientRequestId',
  );
  @override
  late final GeneratedColumn<String> clientRequestId = GeneratedColumn<String>(
    'client_request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SyncStatus>($FoodEntriesTable.$convertersyncStatus);
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<String> serverUpdatedAt = GeneratedColumn<String>(
    'server_updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _datetimeUtcMeta = const VerificationMeta(
    'datetimeUtc',
  );
  @override
  late final GeneratedColumn<String> datetimeUtc = GeneratedColumn<String>(
    'datetime_utc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodIdMeta = const VerificationMeta('foodId');
  @override
  late final GeneratedColumn<String> foodId = GeneratedColumn<String>(
    'food_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES foods (id)',
    ),
  );
  static const VerificationMeta _amountGMeta = const VerificationMeta(
    'amountG',
  );
  @override
  late final GeneratedColumn<double> amountG = GeneratedColumn<double>(
    'amount_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<double> kcal = GeneratedColumn<double>(
    'kcal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbGMeta = const VerificationMeta('carbG');
  @override
  late final GeneratedColumn<double> carbG = GeneratedColumn<double>(
    'carb_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EntrySource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EntrySource>($FoodEntriesTable.$convertersource);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<String> createdAtUtc = GeneratedColumn<String>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<String> updatedAtUtc = GeneratedColumn<String>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    userId,
    serverId,
    clientRequestId,
    syncStatus,
    localVersion,
    serverVersion,
    serverUpdatedAt,
    retryCount,
    lastError,
    deleted,
    datetimeUtc,
    localDate,
    foodId,
    amountG,
    kcal,
    proteinG,
    carbG,
    fatG,
    source,
    note,
    createdAtUtc,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'food_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('client_request_id')) {
      context.handle(
        _clientRequestIdMeta,
        clientRequestId.isAcceptableOrUnknown(
          data['client_request_id']!,
          _clientRequestIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientRequestIdMeta);
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('datetime_utc')) {
      context.handle(
        _datetimeUtcMeta,
        datetimeUtc.isAcceptableOrUnknown(
          data['datetime_utc']!,
          _datetimeUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_datetimeUtcMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('food_id')) {
      context.handle(
        _foodIdMeta,
        foodId.isAcceptableOrUnknown(data['food_id']!, _foodIdMeta),
      );
    } else if (isInserting) {
      context.missing(_foodIdMeta);
    }
    if (data.containsKey('amount_g')) {
      context.handle(
        _amountGMeta,
        amountG.isAcceptableOrUnknown(data['amount_g']!, _amountGMeta),
      );
    } else if (isInserting) {
      context.missing(_amountGMeta);
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    } else if (isInserting) {
      context.missing(_kcalMeta);
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    } else if (isInserting) {
      context.missing(_proteinGMeta);
    }
    if (data.containsKey('carb_g')) {
      context.handle(
        _carbGMeta,
        carbG.isAcceptableOrUnknown(data['carb_g']!, _carbGMeta),
      );
    } else if (isInserting) {
      context.missing(_carbGMeta);
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    } else if (isInserting) {
      context.missing(_fatGMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  FoodEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodEntry(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      clientRequestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_request_id'],
      )!,
      syncStatus: $FoodEntriesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_updated_at'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      datetimeUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}datetime_utc'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      foodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_id'],
      )!,
      amountG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount_g'],
      )!,
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      carbG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      source: $FoodEntriesTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $FoodEntriesTable createAlias(String alias) {
    return $FoodEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncStatus, String, String> $convertersyncStatus =
      const EnumNameConverter<SyncStatus>(SyncStatus.values);
  static JsonTypeConverter2<EntrySource, String, String> $convertersource =
      const EnumNameConverter<EntrySource>(EntrySource.values);
}

class FoodEntry extends DataClass implements Insertable<FoodEntry> {
  /// 本地主键（UUIDv4），客户端生成，全生命周期不变。
  final String localId;

  /// 归属用户；未登录为 `anonymous`（T18）。
  final String userId;

  /// 服务端主键，首次同步成功后回填（T4）。
  final String? serverId;

  /// 幂等键（UUIDv4）：每次上行操作生成，重试复用同一键（§2.2）。
  final String clientRequestId;

  /// 四态同步状态（§1.1）。
  final SyncStatus syncStatus;

  /// 本地每次修改 +1。
  final int localVersion;

  /// 最近一次同步成功的服务端版本号（etag 语义）。
  final int? serverVersion;

  /// 最近一次同步成功的服务端时间戳（UTC），LWW 仲裁依据。
  final String? serverUpdatedAt;

  /// 连续重试次数，用于退避计算（§4.2）。
  final int retryCount;

  /// 最近一次失败原因码。
  final String? lastError;

  /// 本地软删标记（tombstone）。
  final bool deleted;

  /// 就餐时间（UTC ISO8601）。
  final String datetimeUtc;

  /// 归属日（本地时区 yyyy-MM-dd，D-07 口径的聚合键）。
  final String localDate;

  /// 关联食物库条目（D-16）。
  final String foodId;

  /// 份量（克）。
  final double amountG;

  /// 营养快照：按份量换算后的热量（kcal）。
  final double kcal;

  /// 营养快照：蛋白质（g）。
  final double proteinG;

  /// 营养快照：碳水（g）。
  final double carbG;

  /// 营养快照：脂肪（g）。
  final double fatG;

  /// 录入方式。
  final EntrySource source;

  /// 备注。
  final String? note;

  /// 本地创建时间（UTC ISO8601）。
  final String createdAtUtc;

  /// 本地最后修改时间（UTC ISO8601）。
  final String updatedAtUtc;
  const FoodEntry({
    required this.localId,
    required this.userId,
    this.serverId,
    required this.clientRequestId,
    required this.syncStatus,
    required this.localVersion,
    this.serverVersion,
    this.serverUpdatedAt,
    required this.retryCount,
    this.lastError,
    required this.deleted,
    required this.datetimeUtc,
    required this.localDate,
    required this.foodId,
    required this.amountG,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.source,
    this.note,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['client_request_id'] = Variable<String>(clientRequestId);
    {
      map['sync_status'] = Variable<String>(
        $FoodEntriesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['local_version'] = Variable<int>(localVersion);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<String>(serverUpdatedAt);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['deleted'] = Variable<bool>(deleted);
    map['datetime_utc'] = Variable<String>(datetimeUtc);
    map['local_date'] = Variable<String>(localDate);
    map['food_id'] = Variable<String>(foodId);
    map['amount_g'] = Variable<double>(amountG);
    map['kcal'] = Variable<double>(kcal);
    map['protein_g'] = Variable<double>(proteinG);
    map['carb_g'] = Variable<double>(carbG);
    map['fat_g'] = Variable<double>(fatG);
    {
      map['source'] = Variable<String>(
        $FoodEntriesTable.$convertersource.toSql(source),
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at_utc'] = Variable<String>(createdAtUtc);
    map['updated_at_utc'] = Variable<String>(updatedAtUtc);
    return map;
  }

  FoodEntriesCompanion toCompanion(bool nullToAbsent) {
    return FoodEntriesCompanion(
      localId: Value(localId),
      userId: Value(userId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      clientRequestId: Value(clientRequestId),
      syncStatus: Value(syncStatus),
      localVersion: Value(localVersion),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      deleted: Value(deleted),
      datetimeUtc: Value(datetimeUtc),
      localDate: Value(localDate),
      foodId: Value(foodId),
      amountG: Value(amountG),
      kcal: Value(kcal),
      proteinG: Value(proteinG),
      carbG: Value(carbG),
      fatG: Value(fatG),
      source: Value(source),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory FoodEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodEntry(
      localId: serializer.fromJson<String>(json['localId']),
      userId: serializer.fromJson<String>(json['userId']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      clientRequestId: serializer.fromJson<String>(json['clientRequestId']),
      syncStatus: $FoodEntriesTable.$convertersyncStatus.fromJson(
        serializer.fromJson<String>(json['syncStatus']),
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
      serverUpdatedAt: serializer.fromJson<String?>(json['serverUpdatedAt']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      datetimeUtc: serializer.fromJson<String>(json['datetimeUtc']),
      localDate: serializer.fromJson<String>(json['localDate']),
      foodId: serializer.fromJson<String>(json['foodId']),
      amountG: serializer.fromJson<double>(json['amountG']),
      kcal: serializer.fromJson<double>(json['kcal']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      carbG: serializer.fromJson<double>(json['carbG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      source: $FoodEntriesTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      note: serializer.fromJson<String?>(json['note']),
      createdAtUtc: serializer.fromJson<String>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<String>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'userId': serializer.toJson<String>(userId),
      'serverId': serializer.toJson<String?>(serverId),
      'clientRequestId': serializer.toJson<String>(clientRequestId),
      'syncStatus': serializer.toJson<String>(
        $FoodEntriesTable.$convertersyncStatus.toJson(syncStatus),
      ),
      'localVersion': serializer.toJson<int>(localVersion),
      'serverVersion': serializer.toJson<int?>(serverVersion),
      'serverUpdatedAt': serializer.toJson<String?>(serverUpdatedAt),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
      'deleted': serializer.toJson<bool>(deleted),
      'datetimeUtc': serializer.toJson<String>(datetimeUtc),
      'localDate': serializer.toJson<String>(localDate),
      'foodId': serializer.toJson<String>(foodId),
      'amountG': serializer.toJson<double>(amountG),
      'kcal': serializer.toJson<double>(kcal),
      'proteinG': serializer.toJson<double>(proteinG),
      'carbG': serializer.toJson<double>(carbG),
      'fatG': serializer.toJson<double>(fatG),
      'source': serializer.toJson<String>(
        $FoodEntriesTable.$convertersource.toJson(source),
      ),
      'note': serializer.toJson<String?>(note),
      'createdAtUtc': serializer.toJson<String>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<String>(updatedAtUtc),
    };
  }

  FoodEntry copyWith({
    String? localId,
    String? userId,
    Value<String?> serverId = const Value.absent(),
    String? clientRequestId,
    SyncStatus? syncStatus,
    int? localVersion,
    Value<int?> serverVersion = const Value.absent(),
    Value<String?> serverUpdatedAt = const Value.absent(),
    int? retryCount,
    Value<String?> lastError = const Value.absent(),
    bool? deleted,
    String? datetimeUtc,
    String? localDate,
    String? foodId,
    double? amountG,
    double? kcal,
    double? proteinG,
    double? carbG,
    double? fatG,
    EntrySource? source,
    Value<String?> note = const Value.absent(),
    String? createdAtUtc,
    String? updatedAtUtc,
  }) => FoodEntry(
    localId: localId ?? this.localId,
    userId: userId ?? this.userId,
    serverId: serverId.present ? serverId.value : this.serverId,
    clientRequestId: clientRequestId ?? this.clientRequestId,
    syncStatus: syncStatus ?? this.syncStatus,
    localVersion: localVersion ?? this.localVersion,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError.present ? lastError.value : this.lastError,
    deleted: deleted ?? this.deleted,
    datetimeUtc: datetimeUtc ?? this.datetimeUtc,
    localDate: localDate ?? this.localDate,
    foodId: foodId ?? this.foodId,
    amountG: amountG ?? this.amountG,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbG: carbG ?? this.carbG,
    fatG: fatG ?? this.fatG,
    source: source ?? this.source,
    note: note.present ? note.value : this.note,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  FoodEntry copyWithCompanion(FoodEntriesCompanion data) {
    return FoodEntry(
      localId: data.localId.present ? data.localId.value : this.localId,
      userId: data.userId.present ? data.userId.value : this.userId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      clientRequestId: data.clientRequestId.present
          ? data.clientRequestId.value
          : this.clientRequestId,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      datetimeUtc: data.datetimeUtc.present
          ? data.datetimeUtc.value
          : this.datetimeUtc,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      foodId: data.foodId.present ? data.foodId.value : this.foodId,
      amountG: data.amountG.present ? data.amountG.value : this.amountG,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      carbG: data.carbG.present ? data.carbG.value : this.carbG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      source: data.source.present ? data.source.value : this.source,
      note: data.note.present ? data.note.value : this.note,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodEntry(')
          ..write('localId: $localId, ')
          ..write('userId: $userId, ')
          ..write('serverId: $serverId, ')
          ..write('clientRequestId: $clientRequestId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localVersion: $localVersion, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('deleted: $deleted, ')
          ..write('datetimeUtc: $datetimeUtc, ')
          ..write('localDate: $localDate, ')
          ..write('foodId: $foodId, ')
          ..write('amountG: $amountG, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('source: $source, ')
          ..write('note: $note, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    localId,
    userId,
    serverId,
    clientRequestId,
    syncStatus,
    localVersion,
    serverVersion,
    serverUpdatedAt,
    retryCount,
    lastError,
    deleted,
    datetimeUtc,
    localDate,
    foodId,
    amountG,
    kcal,
    proteinG,
    carbG,
    fatG,
    source,
    note,
    createdAtUtc,
    updatedAtUtc,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodEntry &&
          other.localId == this.localId &&
          other.userId == this.userId &&
          other.serverId == this.serverId &&
          other.clientRequestId == this.clientRequestId &&
          other.syncStatus == this.syncStatus &&
          other.localVersion == this.localVersion &&
          other.serverVersion == this.serverVersion &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError &&
          other.deleted == this.deleted &&
          other.datetimeUtc == this.datetimeUtc &&
          other.localDate == this.localDate &&
          other.foodId == this.foodId &&
          other.amountG == this.amountG &&
          other.kcal == this.kcal &&
          other.proteinG == this.proteinG &&
          other.carbG == this.carbG &&
          other.fatG == this.fatG &&
          other.source == this.source &&
          other.note == this.note &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class FoodEntriesCompanion extends UpdateCompanion<FoodEntry> {
  final Value<String> localId;
  final Value<String> userId;
  final Value<String?> serverId;
  final Value<String> clientRequestId;
  final Value<SyncStatus> syncStatus;
  final Value<int> localVersion;
  final Value<int?> serverVersion;
  final Value<String?> serverUpdatedAt;
  final Value<int> retryCount;
  final Value<String?> lastError;
  final Value<bool> deleted;
  final Value<String> datetimeUtc;
  final Value<String> localDate;
  final Value<String> foodId;
  final Value<double> amountG;
  final Value<double> kcal;
  final Value<double> proteinG;
  final Value<double> carbG;
  final Value<double> fatG;
  final Value<EntrySource> source;
  final Value<String?> note;
  final Value<String> createdAtUtc;
  final Value<String> updatedAtUtc;
  final Value<int> rowid;
  const FoodEntriesCompanion({
    this.localId = const Value.absent(),
    this.userId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.clientRequestId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.deleted = const Value.absent(),
    this.datetimeUtc = const Value.absent(),
    this.localDate = const Value.absent(),
    this.foodId = const Value.absent(),
    this.amountG = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.source = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodEntriesCompanion.insert({
    required String localId,
    required String userId,
    this.serverId = const Value.absent(),
    required String clientRequestId,
    required SyncStatus syncStatus,
    this.localVersion = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.deleted = const Value.absent(),
    required String datetimeUtc,
    required String localDate,
    required String foodId,
    required double amountG,
    required double kcal,
    required double proteinG,
    required double carbG,
    required double fatG,
    required EntrySource source,
    this.note = const Value.absent(),
    required String createdAtUtc,
    required String updatedAtUtc,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       userId = Value(userId),
       clientRequestId = Value(clientRequestId),
       syncStatus = Value(syncStatus),
       datetimeUtc = Value(datetimeUtc),
       localDate = Value(localDate),
       foodId = Value(foodId),
       amountG = Value(amountG),
       kcal = Value(kcal),
       proteinG = Value(proteinG),
       carbG = Value(carbG),
       fatG = Value(fatG),
       source = Value(source),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<FoodEntry> custom({
    Expression<String>? localId,
    Expression<String>? userId,
    Expression<String>? serverId,
    Expression<String>? clientRequestId,
    Expression<String>? syncStatus,
    Expression<int>? localVersion,
    Expression<int>? serverVersion,
    Expression<String>? serverUpdatedAt,
    Expression<int>? retryCount,
    Expression<String>? lastError,
    Expression<bool>? deleted,
    Expression<String>? datetimeUtc,
    Expression<String>? localDate,
    Expression<String>? foodId,
    Expression<double>? amountG,
    Expression<double>? kcal,
    Expression<double>? proteinG,
    Expression<double>? carbG,
    Expression<double>? fatG,
    Expression<String>? source,
    Expression<String>? note,
    Expression<String>? createdAtUtc,
    Expression<String>? updatedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (userId != null) 'user_id': userId,
      if (serverId != null) 'server_id': serverId,
      if (clientRequestId != null) 'client_request_id': clientRequestId,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (localVersion != null) 'local_version': localVersion,
      if (serverVersion != null) 'server_version': serverVersion,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (deleted != null) 'deleted': deleted,
      if (datetimeUtc != null) 'datetime_utc': datetimeUtc,
      if (localDate != null) 'local_date': localDate,
      if (foodId != null) 'food_id': foodId,
      if (amountG != null) 'amount_g': amountG,
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbG != null) 'carb_g': carbG,
      if (fatG != null) 'fat_g': fatG,
      if (source != null) 'source': source,
      if (note != null) 'note': note,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodEntriesCompanion copyWith({
    Value<String>? localId,
    Value<String>? userId,
    Value<String?>? serverId,
    Value<String>? clientRequestId,
    Value<SyncStatus>? syncStatus,
    Value<int>? localVersion,
    Value<int?>? serverVersion,
    Value<String?>? serverUpdatedAt,
    Value<int>? retryCount,
    Value<String?>? lastError,
    Value<bool>? deleted,
    Value<String>? datetimeUtc,
    Value<String>? localDate,
    Value<String>? foodId,
    Value<double>? amountG,
    Value<double>? kcal,
    Value<double>? proteinG,
    Value<double>? carbG,
    Value<double>? fatG,
    Value<EntrySource>? source,
    Value<String?>? note,
    Value<String>? createdAtUtc,
    Value<String>? updatedAtUtc,
    Value<int>? rowid,
  }) {
    return FoodEntriesCompanion(
      localId: localId ?? this.localId,
      userId: userId ?? this.userId,
      serverId: serverId ?? this.serverId,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      syncStatus: syncStatus ?? this.syncStatus,
      localVersion: localVersion ?? this.localVersion,
      serverVersion: serverVersion ?? this.serverVersion,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      deleted: deleted ?? this.deleted,
      datetimeUtc: datetimeUtc ?? this.datetimeUtc,
      localDate: localDate ?? this.localDate,
      foodId: foodId ?? this.foodId,
      amountG: amountG ?? this.amountG,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbG: carbG ?? this.carbG,
      fatG: fatG ?? this.fatG,
      source: source ?? this.source,
      note: note ?? this.note,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (clientRequestId.present) {
      map['client_request_id'] = Variable<String>(clientRequestId.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $FoodEntriesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<String>(serverUpdatedAt.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (datetimeUtc.present) {
      map['datetime_utc'] = Variable<String>(datetimeUtc.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (foodId.present) {
      map['food_id'] = Variable<String>(foodId.value);
    }
    if (amountG.present) {
      map['amount_g'] = Variable<double>(amountG.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<double>(kcal.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (carbG.present) {
      map['carb_g'] = Variable<double>(carbG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $FoodEntriesTable.$convertersource.toSql(source.value),
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<String>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<String>(updatedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodEntriesCompanion(')
          ..write('localId: $localId, ')
          ..write('userId: $userId, ')
          ..write('serverId: $serverId, ')
          ..write('clientRequestId: $clientRequestId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localVersion: $localVersion, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('deleted: $deleted, ')
          ..write('datetimeUtc: $datetimeUtc, ')
          ..write('localDate: $localDate, ')
          ..write('foodId: $foodId, ')
          ..write('amountG: $amountG, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('source: $source, ')
          ..write('note: $note, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyNutritionCachesTable extends DailyNutritionCaches
    with TableInfo<$DailyNutritionCachesTable, DailyNutritionCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyNutritionCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryCountMeta = const VerificationMeta(
    'entryCount',
  );
  @override
  late final GeneratedColumn<int> entryCount = GeneratedColumn<int>(
    'entry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<double> kcal = GeneratedColumn<double>(
    'kcal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _carbGMeta = const VerificationMeta('carbG');
  @override
  late final GeneratedColumn<double> carbG = GeneratedColumn<double>(
    'carb_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isLocalEstimateMeta = const VerificationMeta(
    'isLocalEstimate',
  );
  @override
  late final GeneratedColumn<bool> isLocalEstimate = GeneratedColumn<bool>(
    'is_local_estimate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_local_estimate" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<String> updatedAtUtc = GeneratedColumn<String>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    date,
    entryCount,
    kcal,
    proteinG,
    carbG,
    fatG,
    isLocalEstimate,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_nutrition_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyNutritionCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('entry_count')) {
      context.handle(
        _entryCountMeta,
        entryCount.isAcceptableOrUnknown(data['entry_count']!, _entryCountMeta),
      );
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    }
    if (data.containsKey('carb_g')) {
      context.handle(
        _carbGMeta,
        carbG.isAcceptableOrUnknown(data['carb_g']!, _carbGMeta),
      );
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    }
    if (data.containsKey('is_local_estimate')) {
      context.handle(
        _isLocalEstimateMeta,
        isLocalEstimate.isAcceptableOrUnknown(
          data['is_local_estimate']!,
          _isLocalEstimateMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, date};
  @override
  DailyNutritionCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyNutritionCache(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      entryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_count'],
      )!,
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      carbG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      isLocalEstimate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_local_estimate'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $DailyNutritionCachesTable createAlias(String alias) {
    return $DailyNutritionCachesTable(attachedDatabase, alias);
  }
}

class DailyNutritionCache extends DataClass
    implements Insertable<DailyNutritionCache> {
  /// 归属用户。
  final String userId;

  /// 归属日（本地时区 yyyy-MM-dd）。
  final String date;

  /// 当日记录条数。
  final int entryCount;

  /// 累计热量（kcal）。
  final double kcal;

  /// 累计蛋白质（g）。
  final double proteinG;

  /// 累计碳水（g）。
  final double carbG;

  /// 累计脂肪（g）。
  final double fatG;

  /// 是否本地预估值（§2.6）；联网后以下行服务端值为准覆盖。
  final bool isLocalEstimate;

  /// 最近重算时间（UTC ISO8601）。
  final String updatedAtUtc;
  const DailyNutritionCache({
    required this.userId,
    required this.date,
    required this.entryCount,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.isLocalEstimate,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['date'] = Variable<String>(date);
    map['entry_count'] = Variable<int>(entryCount);
    map['kcal'] = Variable<double>(kcal);
    map['protein_g'] = Variable<double>(proteinG);
    map['carb_g'] = Variable<double>(carbG);
    map['fat_g'] = Variable<double>(fatG);
    map['is_local_estimate'] = Variable<bool>(isLocalEstimate);
    map['updated_at_utc'] = Variable<String>(updatedAtUtc);
    return map;
  }

  DailyNutritionCachesCompanion toCompanion(bool nullToAbsent) {
    return DailyNutritionCachesCompanion(
      userId: Value(userId),
      date: Value(date),
      entryCount: Value(entryCount),
      kcal: Value(kcal),
      proteinG: Value(proteinG),
      carbG: Value(carbG),
      fatG: Value(fatG),
      isLocalEstimate: Value(isLocalEstimate),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory DailyNutritionCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyNutritionCache(
      userId: serializer.fromJson<String>(json['userId']),
      date: serializer.fromJson<String>(json['date']),
      entryCount: serializer.fromJson<int>(json['entryCount']),
      kcal: serializer.fromJson<double>(json['kcal']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      carbG: serializer.fromJson<double>(json['carbG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      isLocalEstimate: serializer.fromJson<bool>(json['isLocalEstimate']),
      updatedAtUtc: serializer.fromJson<String>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'date': serializer.toJson<String>(date),
      'entryCount': serializer.toJson<int>(entryCount),
      'kcal': serializer.toJson<double>(kcal),
      'proteinG': serializer.toJson<double>(proteinG),
      'carbG': serializer.toJson<double>(carbG),
      'fatG': serializer.toJson<double>(fatG),
      'isLocalEstimate': serializer.toJson<bool>(isLocalEstimate),
      'updatedAtUtc': serializer.toJson<String>(updatedAtUtc),
    };
  }

  DailyNutritionCache copyWith({
    String? userId,
    String? date,
    int? entryCount,
    double? kcal,
    double? proteinG,
    double? carbG,
    double? fatG,
    bool? isLocalEstimate,
    String? updatedAtUtc,
  }) => DailyNutritionCache(
    userId: userId ?? this.userId,
    date: date ?? this.date,
    entryCount: entryCount ?? this.entryCount,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbG: carbG ?? this.carbG,
    fatG: fatG ?? this.fatG,
    isLocalEstimate: isLocalEstimate ?? this.isLocalEstimate,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  DailyNutritionCache copyWithCompanion(DailyNutritionCachesCompanion data) {
    return DailyNutritionCache(
      userId: data.userId.present ? data.userId.value : this.userId,
      date: data.date.present ? data.date.value : this.date,
      entryCount: data.entryCount.present
          ? data.entryCount.value
          : this.entryCount,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      carbG: data.carbG.present ? data.carbG.value : this.carbG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      isLocalEstimate: data.isLocalEstimate.present
          ? data.isLocalEstimate.value
          : this.isLocalEstimate,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyNutritionCache(')
          ..write('userId: $userId, ')
          ..write('date: $date, ')
          ..write('entryCount: $entryCount, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('isLocalEstimate: $isLocalEstimate, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    date,
    entryCount,
    kcal,
    proteinG,
    carbG,
    fatG,
    isLocalEstimate,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyNutritionCache &&
          other.userId == this.userId &&
          other.date == this.date &&
          other.entryCount == this.entryCount &&
          other.kcal == this.kcal &&
          other.proteinG == this.proteinG &&
          other.carbG == this.carbG &&
          other.fatG == this.fatG &&
          other.isLocalEstimate == this.isLocalEstimate &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class DailyNutritionCachesCompanion
    extends UpdateCompanion<DailyNutritionCache> {
  final Value<String> userId;
  final Value<String> date;
  final Value<int> entryCount;
  final Value<double> kcal;
  final Value<double> proteinG;
  final Value<double> carbG;
  final Value<double> fatG;
  final Value<bool> isLocalEstimate;
  final Value<String> updatedAtUtc;
  final Value<int> rowid;
  const DailyNutritionCachesCompanion({
    this.userId = const Value.absent(),
    this.date = const Value.absent(),
    this.entryCount = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.isLocalEstimate = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyNutritionCachesCompanion.insert({
    required String userId,
    required String date,
    this.entryCount = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.isLocalEstimate = const Value.absent(),
    required String updatedAtUtc,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       date = Value(date),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<DailyNutritionCache> custom({
    Expression<String>? userId,
    Expression<String>? date,
    Expression<int>? entryCount,
    Expression<double>? kcal,
    Expression<double>? proteinG,
    Expression<double>? carbG,
    Expression<double>? fatG,
    Expression<bool>? isLocalEstimate,
    Expression<String>? updatedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (date != null) 'date': date,
      if (entryCount != null) 'entry_count': entryCount,
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbG != null) 'carb_g': carbG,
      if (fatG != null) 'fat_g': fatG,
      if (isLocalEstimate != null) 'is_local_estimate': isLocalEstimate,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyNutritionCachesCompanion copyWith({
    Value<String>? userId,
    Value<String>? date,
    Value<int>? entryCount,
    Value<double>? kcal,
    Value<double>? proteinG,
    Value<double>? carbG,
    Value<double>? fatG,
    Value<bool>? isLocalEstimate,
    Value<String>? updatedAtUtc,
    Value<int>? rowid,
  }) {
    return DailyNutritionCachesCompanion(
      userId: userId ?? this.userId,
      date: date ?? this.date,
      entryCount: entryCount ?? this.entryCount,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbG: carbG ?? this.carbG,
      fatG: fatG ?? this.fatG,
      isLocalEstimate: isLocalEstimate ?? this.isLocalEstimate,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (entryCount.present) {
      map['entry_count'] = Variable<int>(entryCount.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<double>(kcal.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (carbG.present) {
      map['carb_g'] = Variable<double>(carbG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (isLocalEstimate.present) {
      map['is_local_estimate'] = Variable<bool>(isLocalEstimate.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<String>(updatedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyNutritionCachesCompanion(')
          ..write('userId: $userId, ')
          ..write('date: $date, ')
          ..write('entryCount: $entryCount, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('isLocalEstimate: $isLocalEstimate, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoodsTable foods = $FoodsTable(this);
  late final $FoodEntriesTable foodEntries = $FoodEntriesTable(this);
  late final $DailyNutritionCachesTable dailyNutritionCaches =
      $DailyNutritionCachesTable(this);
  late final FoodDao foodDao = FoodDao(this as AppDatabase);
  late final FoodEntryDao foodEntryDao = FoodEntryDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    foods,
    foodEntries,
    dailyNutritionCaches,
  ];
}

typedef $$FoodsTableCreateCompanionBuilder =
    FoodsCompanion Function({
      required String id,
      required String nameZh,
      required String nameEn,
      Value<String> aliasesZh,
      Value<String> aliasesEn,
      required double kcalPer100g,
      required double proteinPer100g,
      required double carbPer100g,
      required double fatPer100g,
      Value<int> rowid,
    });
typedef $$FoodsTableUpdateCompanionBuilder =
    FoodsCompanion Function({
      Value<String> id,
      Value<String> nameZh,
      Value<String> nameEn,
      Value<String> aliasesZh,
      Value<String> aliasesEn,
      Value<double> kcalPer100g,
      Value<double> proteinPer100g,
      Value<double> carbPer100g,
      Value<double> fatPer100g,
      Value<int> rowid,
    });

final class $$FoodsTableReferences
    extends BaseReferences<_$AppDatabase, $FoodsTable, Food> {
  $$FoodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FoodEntriesTable, List<FoodEntry>>
  _foodEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.foodEntries,
    aliasName: 'foods__id__food_entries__food_id',
  );

  $$FoodEntriesTableProcessedTableManager get foodEntriesRefs {
    final manager = $$FoodEntriesTableTableManager(
      $_db,
      $_db.foodEntries,
    ).filter((f) => f.foodId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_foodEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoodsTableFilterComposer extends Composer<_$AppDatabase, $FoodsTable> {
  $$FoodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameZh => $composableBuilder(
    column: $table.nameZh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliasesZh => $composableBuilder(
    column: $table.aliasesZh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliasesEn => $composableBuilder(
    column: $table.aliasesEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbPer100g => $composableBuilder(
    column: $table.carbPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> foodEntriesRefs(
    Expression<bool> Function($$FoodEntriesTableFilterComposer f) f,
  ) {
    final $$FoodEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.foodEntries,
      getReferencedColumn: (t) => t.foodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodEntriesTableFilterComposer(
            $db: $db,
            $table: $db.foodEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoodsTableOrderingComposer
    extends Composer<_$AppDatabase, $FoodsTable> {
  $$FoodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameZh => $composableBuilder(
    column: $table.nameZh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliasesZh => $composableBuilder(
    column: $table.aliasesZh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliasesEn => $composableBuilder(
    column: $table.aliasesEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbPer100g => $composableBuilder(
    column: $table.carbPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoodsTable> {
  $$FoodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nameZh =>
      $composableBuilder(column: $table.nameZh, builder: (column) => column);

  GeneratedColumn<String> get nameEn =>
      $composableBuilder(column: $table.nameEn, builder: (column) => column);

  GeneratedColumn<String> get aliasesZh =>
      $composableBuilder(column: $table.aliasesZh, builder: (column) => column);

  GeneratedColumn<String> get aliasesEn =>
      $composableBuilder(column: $table.aliasesEn, builder: (column) => column);

  GeneratedColumn<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get carbPer100g => $composableBuilder(
    column: $table.carbPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => column,
  );

  Expression<T> foodEntriesRefs<T extends Object>(
    Expression<T> Function($$FoodEntriesTableAnnotationComposer a) f,
  ) {
    final $$FoodEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.foodEntries,
      getReferencedColumn: (t) => t.foodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.foodEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoodsTable,
          Food,
          $$FoodsTableFilterComposer,
          $$FoodsTableOrderingComposer,
          $$FoodsTableAnnotationComposer,
          $$FoodsTableCreateCompanionBuilder,
          $$FoodsTableUpdateCompanionBuilder,
          (Food, $$FoodsTableReferences),
          Food,
          PrefetchHooks Function({bool foodEntriesRefs})
        > {
  $$FoodsTableTableManager(_$AppDatabase db, $FoodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> nameZh = const Value.absent(),
                Value<String> nameEn = const Value.absent(),
                Value<String> aliasesZh = const Value.absent(),
                Value<String> aliasesEn = const Value.absent(),
                Value<double> kcalPer100g = const Value.absent(),
                Value<double> proteinPer100g = const Value.absent(),
                Value<double> carbPer100g = const Value.absent(),
                Value<double> fatPer100g = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodsCompanion(
                id: id,
                nameZh: nameZh,
                nameEn: nameEn,
                aliasesZh: aliasesZh,
                aliasesEn: aliasesEn,
                kcalPer100g: kcalPer100g,
                proteinPer100g: proteinPer100g,
                carbPer100g: carbPer100g,
                fatPer100g: fatPer100g,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String nameZh,
                required String nameEn,
                Value<String> aliasesZh = const Value.absent(),
                Value<String> aliasesEn = const Value.absent(),
                required double kcalPer100g,
                required double proteinPer100g,
                required double carbPer100g,
                required double fatPer100g,
                Value<int> rowid = const Value.absent(),
              }) => FoodsCompanion.insert(
                id: id,
                nameZh: nameZh,
                nameEn: nameEn,
                aliasesZh: aliasesZh,
                aliasesEn: aliasesEn,
                kcalPer100g: kcalPer100g,
                proteinPer100g: proteinPer100g,
                carbPer100g: carbPer100g,
                fatPer100g: fatPer100g,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$FoodsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({foodEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (foodEntriesRefs) db.foodEntries],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (foodEntriesRefs)
                    await $_getPrefetchedData<Food, $FoodsTable, FoodEntry>(
                      currentTable: table,
                      referencedTable: $$FoodsTableReferences
                          ._foodEntriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FoodsTableReferences(db, table, p0).foodEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.foodId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FoodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoodsTable,
      Food,
      $$FoodsTableFilterComposer,
      $$FoodsTableOrderingComposer,
      $$FoodsTableAnnotationComposer,
      $$FoodsTableCreateCompanionBuilder,
      $$FoodsTableUpdateCompanionBuilder,
      (Food, $$FoodsTableReferences),
      Food,
      PrefetchHooks Function({bool foodEntriesRefs})
    >;
typedef $$FoodEntriesTableCreateCompanionBuilder =
    FoodEntriesCompanion Function({
      required String localId,
      required String userId,
      Value<String?> serverId,
      required String clientRequestId,
      required SyncStatus syncStatus,
      Value<int> localVersion,
      Value<int?> serverVersion,
      Value<String?> serverUpdatedAt,
      Value<int> retryCount,
      Value<String?> lastError,
      Value<bool> deleted,
      required String datetimeUtc,
      required String localDate,
      required String foodId,
      required double amountG,
      required double kcal,
      required double proteinG,
      required double carbG,
      required double fatG,
      required EntrySource source,
      Value<String?> note,
      required String createdAtUtc,
      required String updatedAtUtc,
      Value<int> rowid,
    });
typedef $$FoodEntriesTableUpdateCompanionBuilder =
    FoodEntriesCompanion Function({
      Value<String> localId,
      Value<String> userId,
      Value<String?> serverId,
      Value<String> clientRequestId,
      Value<SyncStatus> syncStatus,
      Value<int> localVersion,
      Value<int?> serverVersion,
      Value<String?> serverUpdatedAt,
      Value<int> retryCount,
      Value<String?> lastError,
      Value<bool> deleted,
      Value<String> datetimeUtc,
      Value<String> localDate,
      Value<String> foodId,
      Value<double> amountG,
      Value<double> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<EntrySource> source,
      Value<String?> note,
      Value<String> createdAtUtc,
      Value<String> updatedAtUtc,
      Value<int> rowid,
    });

final class $$FoodEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $FoodEntriesTable, FoodEntry> {
  $$FoodEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoodsTable _foodIdTable(_$AppDatabase db) =>
      db.foods.createAlias('food_entries__food_id__foods__id');

  $$FoodsTableProcessedTableManager get foodId {
    final $_column = $_itemColumn<String>('food_id')!;

    final manager = $$FoodsTableTableManager(
      $_db,
      $_db.foods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_foodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FoodEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $FoodEntriesTable> {
  $$FoodEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientRequestId => $composableBuilder(
    column: $table.clientRequestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, String>
  get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datetimeUtc => $composableBuilder(
    column: $table.datetimeUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountG => $composableBuilder(
    column: $table.amountG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EntrySource, EntrySource, String> get source =>
      $composableBuilder(
        column: $table.source,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$FoodsTableFilterComposer get foodId {
    final $$FoodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableFilterComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoodEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $FoodEntriesTable> {
  $$FoodEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientRequestId => $composableBuilder(
    column: $table.clientRequestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datetimeUtc => $composableBuilder(
    column: $table.datetimeUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountG => $composableBuilder(
    column: $table.amountG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoodsTableOrderingComposer get foodId {
    final $$FoodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableOrderingComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoodEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoodEntriesTable> {
  $$FoodEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get clientRequestId => $composableBuilder(
    column: $table.clientRequestId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SyncStatus, String> get syncStatus =>
      $composableBuilder(
        column: $table.syncStatus,
        builder: (column) => column,
      );

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get datetimeUtc => $composableBuilder(
    column: $table.datetimeUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<double> get amountG =>
      $composableBuilder(column: $table.amountG, builder: (column) => column);

  GeneratedColumn<double> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get carbG =>
      $composableBuilder(column: $table.carbG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EntrySource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  $$FoodsTableAnnotationComposer get foodId {
    final $$FoodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodId,
      referencedTable: $db.foods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodsTableAnnotationComposer(
            $db: $db,
            $table: $db.foods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoodEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoodEntriesTable,
          FoodEntry,
          $$FoodEntriesTableFilterComposer,
          $$FoodEntriesTableOrderingComposer,
          $$FoodEntriesTableAnnotationComposer,
          $$FoodEntriesTableCreateCompanionBuilder,
          $$FoodEntriesTableUpdateCompanionBuilder,
          (FoodEntry, $$FoodEntriesTableReferences),
          FoodEntry,
          PrefetchHooks Function({bool foodId})
        > {
  $$FoodEntriesTableTableManager(_$AppDatabase db, $FoodEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> clientRequestId = const Value.absent(),
                Value<SyncStatus> syncStatus = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String?> serverUpdatedAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> datetimeUtc = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> foodId = const Value.absent(),
                Value<double> amountG = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<EntrySource> source = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> createdAtUtc = const Value.absent(),
                Value<String> updatedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodEntriesCompanion(
                localId: localId,
                userId: userId,
                serverId: serverId,
                clientRequestId: clientRequestId,
                syncStatus: syncStatus,
                localVersion: localVersion,
                serverVersion: serverVersion,
                serverUpdatedAt: serverUpdatedAt,
                retryCount: retryCount,
                lastError: lastError,
                deleted: deleted,
                datetimeUtc: datetimeUtc,
                localDate: localDate,
                foodId: foodId,
                amountG: amountG,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                source: source,
                note: note,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                required String userId,
                Value<String?> serverId = const Value.absent(),
                required String clientRequestId,
                required SyncStatus syncStatus,
                Value<int> localVersion = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String?> serverUpdatedAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String datetimeUtc,
                required String localDate,
                required String foodId,
                required double amountG,
                required double kcal,
                required double proteinG,
                required double carbG,
                required double fatG,
                required EntrySource source,
                Value<String?> note = const Value.absent(),
                required String createdAtUtc,
                required String updatedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => FoodEntriesCompanion.insert(
                localId: localId,
                userId: userId,
                serverId: serverId,
                clientRequestId: clientRequestId,
                syncStatus: syncStatus,
                localVersion: localVersion,
                serverVersion: serverVersion,
                serverUpdatedAt: serverUpdatedAt,
                retryCount: retryCount,
                lastError: lastError,
                deleted: deleted,
                datetimeUtc: datetimeUtc,
                localDate: localDate,
                foodId: foodId,
                amountG: amountG,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                source: source,
                note: note,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FoodEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({foodId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (foodId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.foodId,
                                referencedTable: $$FoodEntriesTableReferences
                                    ._foodIdTable(db),
                                referencedColumn: $$FoodEntriesTableReferences
                                    ._foodIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FoodEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoodEntriesTable,
      FoodEntry,
      $$FoodEntriesTableFilterComposer,
      $$FoodEntriesTableOrderingComposer,
      $$FoodEntriesTableAnnotationComposer,
      $$FoodEntriesTableCreateCompanionBuilder,
      $$FoodEntriesTableUpdateCompanionBuilder,
      (FoodEntry, $$FoodEntriesTableReferences),
      FoodEntry,
      PrefetchHooks Function({bool foodId})
    >;
typedef $$DailyNutritionCachesTableCreateCompanionBuilder =
    DailyNutritionCachesCompanion Function({
      required String userId,
      required String date,
      Value<int> entryCount,
      Value<double> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<bool> isLocalEstimate,
      required String updatedAtUtc,
      Value<int> rowid,
    });
typedef $$DailyNutritionCachesTableUpdateCompanionBuilder =
    DailyNutritionCachesCompanion Function({
      Value<String> userId,
      Value<String> date,
      Value<int> entryCount,
      Value<double> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<bool> isLocalEstimate,
      Value<String> updatedAtUtc,
      Value<int> rowid,
    });

class $$DailyNutritionCachesTableFilterComposer
    extends Composer<_$AppDatabase, $DailyNutritionCachesTable> {
  $$DailyNutritionCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryCount => $composableBuilder(
    column: $table.entryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocalEstimate => $composableBuilder(
    column: $table.isLocalEstimate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyNutritionCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyNutritionCachesTable> {
  $$DailyNutritionCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryCount => $composableBuilder(
    column: $table.entryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocalEstimate => $composableBuilder(
    column: $table.isLocalEstimate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyNutritionCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyNutritionCachesTable> {
  $$DailyNutritionCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get entryCount => $composableBuilder(
    column: $table.entryCount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get carbG =>
      $composableBuilder(column: $table.carbG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<bool> get isLocalEstimate => $composableBuilder(
    column: $table.isLocalEstimate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$DailyNutritionCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyNutritionCachesTable,
          DailyNutritionCache,
          $$DailyNutritionCachesTableFilterComposer,
          $$DailyNutritionCachesTableOrderingComposer,
          $$DailyNutritionCachesTableAnnotationComposer,
          $$DailyNutritionCachesTableCreateCompanionBuilder,
          $$DailyNutritionCachesTableUpdateCompanionBuilder,
          (
            DailyNutritionCache,
            BaseReferences<
              _$AppDatabase,
              $DailyNutritionCachesTable,
              DailyNutritionCache
            >,
          ),
          DailyNutritionCache,
          PrefetchHooks Function()
        > {
  $$DailyNutritionCachesTableTableManager(
    _$AppDatabase db,
    $DailyNutritionCachesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyNutritionCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyNutritionCachesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DailyNutritionCachesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> entryCount = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<bool> isLocalEstimate = const Value.absent(),
                Value<String> updatedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyNutritionCachesCompanion(
                userId: userId,
                date: date,
                entryCount: entryCount,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                isLocalEstimate: isLocalEstimate,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String date,
                Value<int> entryCount = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<bool> isLocalEstimate = const Value.absent(),
                required String updatedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => DailyNutritionCachesCompanion.insert(
                userId: userId,
                date: date,
                entryCount: entryCount,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                isLocalEstimate: isLocalEstimate,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyNutritionCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyNutritionCachesTable,
      DailyNutritionCache,
      $$DailyNutritionCachesTableFilterComposer,
      $$DailyNutritionCachesTableOrderingComposer,
      $$DailyNutritionCachesTableAnnotationComposer,
      $$DailyNutritionCachesTableCreateCompanionBuilder,
      $$DailyNutritionCachesTableUpdateCompanionBuilder,
      (
        DailyNutritionCache,
        BaseReferences<
          _$AppDatabase,
          $DailyNutritionCachesTable,
          DailyNutritionCache
        >,
      ),
      DailyNutritionCache,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoodsTableTableManager get foods =>
      $$FoodsTableTableManager(_db, _db.foods);
  $$FoodEntriesTableTableManager get foodEntries =>
      $$FoodEntriesTableTableManager(_db, _db.foodEntries);
  $$DailyNutritionCachesTableTableManager get dailyNutritionCaches =>
      $$DailyNutritionCachesTableTableManager(_db, _db.dailyNutritionCaches);
}

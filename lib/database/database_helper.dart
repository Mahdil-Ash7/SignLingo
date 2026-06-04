import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

Future<Database> get database async {
  if (_database != null) return _database!;

  _database = await _initDB('SignLingo.db');
  return _database!;
}

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    // check if DB already exists
    final exists = await File(path).exists();

    if (!exists) {
      print("Copying database from assets...");

      // load from assets
      ByteData data = await rootBundle.load('assets/database/$fileName');

      List<int> bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      await File(path).writeAsBytes(bytes, flush: true);
    }

    print("DB PATH: $path");
    return openDatabase(path);
  }

  Future<List<Map<String, dynamic>>> getAllSigns() async {
  final db = await instance.database;

  return await db.query('signs');
  }

Future<Map<String, String>> getSignsImagePath() async {
  final db = await instance.database;

  final result = await db.query(
    'signs',
    columns: ['label', 'asset_path'],
  );

  return {
    for (var row in result)
      row['label'] as String: row['asset_path'] as String,
  };
}

Future<Map<String, String>> getSignsImagePathByCategory(int id) async {
  final db = await instance.database;

  final result = await db.query(
    'signs',
    where: 'category_id = ?',
    whereArgs: [id],
    columns: ['label', 'asset_path'],
  );

  return {
    for (var row in result)
      row['label'] as String: row['asset_path'] as String,
  };
}

  Future<List<Map<String, dynamic>>> getSignsByCategory(int id) async {
  final db = await instance.database;

  return await db.query(
    'signs',
    where: 'category_id = ?',
    whereArgs: [id],
  );
}

  Future<List<Map<String, dynamic>>> getSignCategories() async{
    final db =  await instance.database;

    return await db.query('sign_categories');
  }
}
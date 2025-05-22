import 'package:flutter/material.dart';

class Product {
  DateTime pickupDate;
  DateTime returnDate;
  String productCode;
  int quantity;
  int? availableQuantity;
  String errorMessage;
  String price;
  String deposit;
  String productName;
  int totalQuantity;
  String? imageUrl;
  String priceType;
  int minimumRentalPeriod;
  int extraRent;

  Product({
    required this.pickupDate,
    required this.returnDate,
    required this.productCode,
    required this.quantity,
    this.availableQuantity,
    this.errorMessage = '',
    this.price = '',
    this.deposit = '',
    this.productName = '',
    this.totalQuantity = 0,
    this.imageUrl,
    this.priceType = 'daily',
    this.minimumRentalPeriod = 1,
    this.extraRent = 0,
  });
}
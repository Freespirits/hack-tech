import 'package:logger/logger.dart';

final Logger appLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: false,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
);

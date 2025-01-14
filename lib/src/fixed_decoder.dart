/* Copyright (C) Brett Sutton - All Rights Reserved
 * Released under the MIT license.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:math';

/// Decodes a monetary amount based on a pattern.
class FixedDecoder {
  /// ctor
  FixedDecoder({
    required this.pattern,
    required this.groupSeparator,
    required this.decimalSeparator,
  }) {
    ArgumentError.checkNotNull(pattern, 'pattern');
  }

  /// the pattern used to decode the amount.
  final String pattern;

  final String decimalSeparator;
  final String groupSeparator;

  /// Parses [monetaryValue] and returns
  /// the value as a BigInt holding the minorUnits
  MinorUnitsAndScale decode(String monetaryValue, int? scale) {
    var majorUnits = BigInt.zero;
    var minorUnits = BigInt.zero;
    // the no. of decimals actually found in the minor units
    var actualScale = 0;

    var compressedPattern = compressDigits(pattern);
    compressedPattern = compressWhitespace(compressedPattern);
    final compressedMonetaryValue = compressWhitespace(monetaryValue);

    var isNegative = false;
    var seenMajor = false;

    final valueQueue = ValueQueue(compressedMonetaryValue, groupSeparator);

    for (var i = 0; i < compressedPattern.length; i++) {
      switch (compressedPattern[i]) {
        case '#':
          if (!seenMajor) {
            final char = valueQueue.peek();
            if (char == '-') {
              valueQueue.takeOne();
              isNegative = true;
            }
          }
          if (seenMajor) {
            if (valueQueue.isNotEmpty) {
              final minorDigits = valueQueue._takeMinorDigits();
              actualScale = minorDigits.scale;
              minorUnits = minorDigits.value;
            }
          } else {
            majorUnits = valueQueue.takeMajorDigits();
          }
          break;
        case '.':
          if (valueQueue.isNotEmpty) {
            final char = valueQueue.takeOne();
            if (char != decimalSeparator) {
              throw FixedParseException.fromValue(
                  compressedPattern: compressedPattern,
                  patternIndex: i,
                  compressedValue: compressedMonetaryValue,
                  monetaryIndex: valueQueue.index,
                  monetaryValue: monetaryValue);
            }
          }
          seenMajor = true;
          break;
        case ' ':
          break;
        default:
          throw FixedParseException(
            'Invalid character "${compressedPattern[i]}" found in pattern.',
          );
      }
    }

    final value = majorUnits * BigInt.from(10).pow(actualScale) + minorUnits;
    return MinorUnitsAndScale(isNegative ? -value : value, actualScale);
  }

  ///
  /// Compresses all 0 # , . characters into a single #.#
  ///
  String compressDigits(String pattern) {
    var result = '';

    final regExPattern =
        '([#|0|$groupSeparator]+)(?:$decimalSeparator([#|0]+))?';

    final regEx = RegExp(regExPattern);

    final matches = regEx.allMatches(pattern);

    if (matches.isEmpty) {
      throw FixedParseException(
        'The pattern did not contain a valid pattern such as "0.00"',
      );
    }

    if (matches.length != 1) {
      throw FixedParseException(
        'The pattern contained more than one numberic pattern.'
        " Check you don't have spaces in the numeric parts of the pattern.",
      );
    }

    final Match match = matches.first;

    if (match.group(1) != null && match.group(2) != null) {
      result = pattern.replaceFirst(regEx, '#.#');
    } else if (match.group(1) != null) {
      result = pattern.replaceFirst(regEx, '#');
    } else if (match.group(2) != null) {
      result = pattern.replaceFirst(regEx, '.#');
    }
    return result;
  }

  /// Removes all whitespace from a pattern or a value
  /// as when we are parsing we ignore whitespace.
  String compressWhitespace(String value) {
    final regEx = RegExp(r'\s+');

    return value.replaceAll(regEx, '');
  }
}

/// Takes a monetary value and turns it into a queue
/// of digits which can be taken one at a time.
class ValueQueue {
  ///
  ValueQueue(this.monetaryValue, this.groupSeparator);

  /// the amount we are queuing the digits of.
  String monetaryValue;

  /// current index into the [monetaryValue]
  int index = 0;

  /// the group seperator used in this [monetaryValue]
  String groupSeparator;

  /// The last character we took from the queue.
  String? lastTake;

  String peek() => monetaryValue[index];

  /// takes the next character from the value.
  String takeOne() => lastTake = monetaryValue[index++];

  bool get isEmpty => monetaryValue.length == index;

  bool get isNotEmpty => !isEmpty;

  /// takes the next [n] character from the value.
  String takeN(int n) {
    var end = index + n;

    end = min(end, monetaryValue.length);
    final take = lastTake = monetaryValue.substring(index, end);

    index += n;

    return take;
  }

  /// return all of the digits from the current position
  /// until we find a non-digit.
  BigInt takeMajorDigits() => BigInt.parse(takeDigits());

  /// true if the passed character is a digit.
  bool isDigit(String char) => RegExp('[0123456789]').hasMatch(char);

  /// Takes any remaining digits as minor digits.
  _MinorDigits _takeMinorDigits() {
    final digits = takeDigits();

    return _MinorDigits(BigInt.parse(digits), digits.length);
  }

  String takeDigits() {
    var digits = ''; //  = lastTake;

    while (index < monetaryValue.length &&
        (isDigit(monetaryValue[index]) ||
            monetaryValue[index] == groupSeparator)) {
      if (monetaryValue[index] != groupSeparator) {
        digits += monetaryValue[index];
      }
      index++;
    }

    if (digits.isEmpty) {
      throw FixedParseException(
        'Character "${monetaryValue[index]}" at pos $index'
        ' is not a digit when a digit was expected',
      );
    }
    return digits;
  }
}

class _MinorDigits {
  _MinorDigits(this.value, this.scale);
  BigInt value;
  int scale;
}

class MinorUnitsAndScale {
  MinorUnitsAndScale(this.value, this.scale);
  BigInt value;
  int scale;
}

/// Exception thrown when a parse fails.
class FixedParseException implements Exception {
  /// Exception thrown when a parse fails.
  FixedParseException(this.message);

  ///
  factory FixedParseException.fromValue(
      {required String compressedPattern,
      required int patternIndex,
      required String compressedValue,
      required int monetaryIndex,
      required String monetaryValue}) {
    final message = '''
$monetaryValue contained an unexpected character '${compressedValue[monetaryIndex]}' at pos $monetaryIndex
        when a match for pattern character ${compressedPattern[patternIndex]} at pos $patternIndex was expected.''';
    return FixedParseException(message);
  }

  /// The error message
  String message;

  @override
  String toString() => message;
}

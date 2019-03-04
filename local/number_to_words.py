#!/usr/bin/env python3
#Author: Peter Smit

import sys

WORDS = {-1: 'nolla',
         0: '',
         1: 'yksi',
         2: 'kaksi',
         3: 'kolme',
         4: 'neljä',
        5: 'viisi',
         6: 'kuusi',
         7: 'seitsemän',
         8: 'kahdeksan',
         9: 'yhdeksän',
         10: 'kymmenen',
         -10: 'toista',
         -11: 'kymmentä',
         100: 'sata',
         1000: 'tuhat',
         }


def get_number_below_hundred(number):
    assert 0 <= number < 100
    if number <= 10:
        return WORDS[number]
    if 11 <= number < 20:
        return WORDS[number % 10] + WORDS[-10]
    return WORDS[number // 10] + WORDS[-11] + WORDS[number % 10]


def get_number_below_thousand(number):
    assert number < 1000
    if number < 100:
        return get_number_below_hundred(number)
    w = ""
    if number >= 200:
        w += WORDS[number // 100]
    w += WORDS[100]
    w += get_number_below_hundred(number % 100)
    return w


def get_number_below_tenthousand(number):
    assert 1000 <= number < 10000

    w1 = ""
    if number >= 2000:
        w1 += WORDS[number // 1000]
    w1 += WORDS[1000]
    w1 += get_number_below_thousand(number % 1000)

    w2 = get_number_below_hundred(number // 100) + WORDS[100] + get_number_below_hundred(number % 100)

    return [w1, w2]


for number in sys.stdin:
    number = number.strip()

    if len(number) > 6:
        exit("Too big number: {}".format(number))

    while len(number) > 0 and number[0] == '0':
        print(WORDS[-1], end="")
        number = number[1:]
    if len(number) == 0:
        continue

    number = int(number)

    if number < 100:
        print(get_number_below_hundred(number))
    elif number < 1000:
        print(get_number_below_thousand(number))
    elif number < 10000:
        options = get_number_below_tenthousand(number)
        print(",".join(options))

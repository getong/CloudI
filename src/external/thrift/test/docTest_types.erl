%%
%% Autogenerated by Thrift Compiler (0.9.0)
%%
%% DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
%%

-module(docTest_types).

-include("docTest_types.hrl").

-export([struct_info/1, struct_info_ext/1]).

struct_info('xtruct') ->
  {struct, [{1, string},
          {4, byte},
          {9, i32},
          {11, i64}]}
;

struct_info('xtruct2') ->
  {struct, [{1, byte},
          {2, {struct, {'docTest_types', 'xtruct'}}},
          {3, i32}]}
;

struct_info('insanity') ->
  {struct, [{1, {map, i32, i64}},
          {2, {list, {struct, {'docTest_types', 'xtruct'}}}}]}
;

struct_info('xception') ->
  {struct, [{1, i32},
          {2, string}]}
;

struct_info('xception2') ->
  {struct, [{1, i32},
          {2, {struct, {'docTest_types', 'xtruct'}}}]}
;

struct_info('emptyStruct') ->
  {struct, []}
;

struct_info('oneField') ->
  {struct, [{1, {struct, {'docTest_types', 'emptyStruct'}}}]}
;

struct_info('i am a dummy struct') -> undefined.

struct_info_ext('xtruct') ->
  {struct, [{1, undefined, string, 'string_thing', undefined},
          {4, undefined, byte, 'byte_thing', undefined},
          {9, undefined, i32, 'i32_thing', undefined},
          {11, undefined, i64, 'i64_thing', undefined}]}
;

struct_info_ext('xtruct2') ->
  {struct, [{1, undefined, byte, 'byte_thing', undefined},
          {2, undefined, {struct, {'docTest_types', 'xtruct'}}, 'struct_thing', #xtruct{}},
          {3, undefined, i32, 'i32_thing', undefined}]}
;

struct_info_ext('insanity') ->
  {struct, [{1, undefined, {map, i32, i64}, 'userMap', dict:new()},
          {2, undefined, {list, {struct, {'docTest_types', 'xtruct'}}}, 'xtructs', []}]}
;

struct_info_ext('xception') ->
  {struct, [{1, undefined, i32, 'errorCode', undefined},
          {2, undefined, string, 'message', undefined}]}
;

struct_info_ext('xception2') ->
  {struct, [{1, undefined, i32, 'errorCode', undefined},
          {2, undefined, {struct, {'docTest_types', 'xtruct'}}, 'struct_thing', #xtruct{}}]}
;

struct_info_ext('emptyStruct') ->
  {struct, []}
;

struct_info_ext('oneField') ->
  {struct, [{1, undefined, {struct, {'docTest_types', 'emptyStruct'}}, 'field', #emptyStruct{}}]}
;

struct_info_ext('i am a dummy struct') -> undefined.


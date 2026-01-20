# org.flashNight.naki.DataStructures.Dictionary

## 简介
`org.flashNight.naki.DataStructures.Dictionary` 类是一个通用的键值对存储容器，允许使用字符串、对象或函数作为键来存储对应的值。该类提供了高效的键值存储、检索、删除等操作，同时支持遍历字典中的所有键值对。与传统的键值存储方式不同，`Dictionary` 类能够处理复杂的数据结构，例如对象和函数作为键。

> **注意**：`Dictionary` 类的性能开销大约是原生 AS2 对象的 1.5 倍，特别是语法糖方法（如 `setItem`、`getItem`、`forEach`）的开销较重。因此，在性能密集的场合应谨慎使用。如果只需要字典的标注去重功能，推荐使用类提供的静态方法来手动实现内部细节。

---

## 主要功能

1. **支持多种类型的键**：
   - 支持字符串、对象和函数作为键。
   - 对象和函数使用唯一标识符（UID）来跟踪，确保唯一识别。

2. **键值对管理**：
   - **添加/更新键值对**：使用 `setItem` 添加或更新字典中的键值对。
   - **获取键对应的值**：使用 `getItem` 获取指定键的值。
   - **删除键值对**：使用 `removeItem` 删除字典中的键值对。
   - **检查键是否存在**：使用 `hasKey` 检查字典中是否存在键。

3. **高级功能**：
   - **获取键列表**：使用 `getKeys` 返回字典中所有键的数组。
   - **字典大小**：使用 `getCount` 获取字典中键值对的数量。
   - **清空字典**：使用 `clear` 清空字典中的所有数据。
   - **销毁字典**：使用 `destroy` 清理所有引用，防止内存泄漏。

4. **性能优化**：
   - **键缓存**：通过 `keysCache` 缓存键列表，避免频繁遍历存储对象，但在大量增删操作后可能需要重新计算缓存。
   - **静态方法优化**：如果只需要对象的唯一标识符（UID），可以利用对外提供的静态方法 `getStaticUID`，避免创建字典实例，提高性能。

---

## API 说明

### 1. 构造函数
```actionscript
public function Dictionary()
```
**功能**：创建一个新的字典实例，初始化存储结构。

### 2. setItem
```actionscript
public function setItem(key, value):Void
```
**功能**：将键值对添加到字典中，支持字符串、对象和函数作为键。如果键已存在，则更新其对应的值。
- `key`：要存储的键（字符串、对象、函数）。
- `value`：与键关联的值。

### 3. getItem
```actionscript
public function getItem(key)
```
**功能**：获取指定键的值。
- `key`：要查找的键（字符串、对象、函数）。
- **返回值**：键对应的值，如果键不存在则返回 `null`。

### 4. removeItem
```actionscript
public function removeItem(key):Void
```
**功能**：从字典中删除指定的键值对。
- `key`：要删除的键（字符串、对象、函数）。

### 5. hasKey
```actionscript
public function hasKey(key):Boolean
```
**功能**：检查字典中是否包含指定的键。
- `key`：要检查的键（字符串、对象、函数）。
- **返回值**：如果键存在，返回 `true`；否则返回 `false`。

### 6. getKeys
```actionscript
public function getKeys():Array
```
**功能**：获取字典中所有键的数组（包括字符串键、对象键和函数键）。
- **返回值**：包含所有键的数组。

### 7. getUID
```actionscript
public function getUID(key:Object):Number
```
**功能**：获取指定对象或函数的唯一标识符（UID）。
- `key`：要获取 UID 的对象或函数。
- **返回值**：该对象或函数对应的唯一标识符，如果对象尚无 UID，会为其分配新的 UID。

### 8. getStaticUID
```actionscript
public static function getStaticUID(key:Object):Number
```
**功能**：为对象或函数分配唯一标识符（UID）。与 `getUID` 不同，该方法不需要实例化字典对象，适用于只需要唯一标识符管理而无需使用完整字典功能的场景。
- `key`：要获取或分配 UID 的对象或函数。
- **返回值**：该对象或函数对应的唯一标识符。如果对象没有 UID，会为其分配一个新的。

> **使用建议**：在性能敏感场合，若只需要对象的标注或去重功能，而不需要存储和检索功能，推荐使用 `getStaticUID` 静态方法。该方法避免了实例化字典对象带来的额外开销。

### 9. clear
```actionscript
public function clear():Void
```
**功能**：清空字典，删除所有键值对。

### 10. getCount
```actionscript
public function getCount():Number
```
**功能**：获取字典中键值对的数量。
- **返回值**：当前字典中的键值对数量。

### 11. forEach
```actionscript
public function forEach(callback:Function):Void
```
**功能**：遍历字典中的所有键值对，并对每个键值对执行回调函数。
- `callback`：回调函数，格式为 `function(key, value)`。

### 12. destroy
```actionscript
public function destroy():Void
```
**功能**：销毁字典，清理所有引用，防止内存泄漏。

---

## 性能注意事项

1. **性能开销**：
   - `Dictionary` 类相较于原生 AS2 对象的性能开销大约是 1.5 倍，特别是涉及对象或函数作为键时，额外的 UID 生成和存储操作会带来额外的性能开销。
   - 使用语法糖方法（如 `setItem`、`getItem`、`forEach`）时，开销会更重。因此，在性能密集型场合下建议谨慎使用这些方法。

2. **静态 UID 方法**：
   - 如果只需要标注或去重功能，可以使用 `getStaticUID` 静态方法，该方法可以在不实例化字典的情况下，为对象或函数分配唯一标识符。

3. **缓存机制**：
   - 字典实现了键缓存机制，避免了频繁计算所有键的开销。但在频繁的增删操作后，缓存可能会失效，导致需要重新计算。

---

## 使用示例

```actionscript
// 创建一个新的字典实例
var dict:Dictionary = new Dictionary();

// 添加字符串键
dict.setItem("name", "Alice");

// 添加对象键
var obj:Object = { id: 1 };
dict.setItem(obj, "对象一");

// 添加函数键
function greet():Void {
    trace("Hello!");
}
dict.setItem(greet, "问候函数");

// 获取值
trace(dict.getItem("name"));     // 输出: Alice
trace(dict.getItem(obj));        // 输出: 对象一
trace(dict.getItem(greet));      // 输出: 问候函数

// 使用静态方法获取对象的唯一 UID
var uid:Number = Dictionary.getStaticUID(obj);
trace(uid);                      // 输出对象的唯一标识符

// 检查键是否存在
trace(dict.hasKey("name"));      // 输出: true
trace(dict.hasKey("unknown"));   // 输出: false

// 获取所有键
var keys:Array = dict.getKeys();
for (var i:Number =

 0; i < keys.length; i++) {
    trace(keys[i]);
}

// 删除键
dict.removeItem("name");

// 获取键值对数量
trace(dict.getCount());         // 输出当前的键值对数量

// 清空字典
dict.clear();
trace(dict.getCount());         // 输出: 0
```

---

## 注意事项

1. **对象键和函数键的处理**：
   使用对象和函数作为键时，字典会为每个对象和函数生成唯一标识符（UID），通过该 UID 来存储和查找值。这确保了即使两个对象具有相同的内容，它们仍然能作为独立的键来处理。

2. **性能**：
   字典类实现了键缓存机制，通过 `keysCache` 缓存键列表，避免频繁遍历存储对象。但在大量增删操作后，缓存可能会失效并需要重新计算。

3. **内存管理**：
   使用 `destroy` 方法来销毁字典并清理所有引用，以防止内存泄漏，特别是在不再使用该字典时。

4. **性能密集场景的建议**：
   在性能密集的场合下，建议谨慎使用 `setItem`、`getItem` 等高开销方法。对于去重和标注功能，可以使用静态方法 `getStaticUID` 实现标注，而不必创建字典实例。
```

---




import org.flashNight.naki.DataStructures.*;

// 执行测试
DictionaryTest.runAll();


=== Starting Correctness Tests ===
Assertion Passed: Empty dictionary count should be 0
Assertion Passed: Empty dictionary keys should be empty
Assertion Passed: Count after adding 2 items
Assertion Passed: String key retrieval 1
Assertion Passed: String key retrieval 2
Assertion Passed: HasKey for existing string key
Assertion Passed: HasKey for non-existent string key
Assertion Passed: Count after removal
Assertion Passed: Removed item should return null
Assertion Passed: Object/function key count
Assertion Passed: Object key retrieval 1
Assertion Passed: Object key retrieval 2
Assertion Passed: Function key retrieval
Assertion Passed: Non-existent function key
Assertion Passed: Different objects with same content should be different keys
Assertion Passed: UID should be a number
Assertion Passed: Instance and static UID should match
Assertion Passed: UID should be consistent
Assertion Passed: New objects should get decrementing UIDs
Assertion Passed: UID should remain after deletion
Assertion Passed: Initial empty keys
Assertion Passed: Keys count after additions
Assertion Passed: String key in keys list
Assertion Passed: Object key in keys list
Assertion Passed: Keys count after removal
Assertion Passed: Remaining key in updated list
Assertion Passed: Count after clear
Assertion Passed: Keys after clear
Assertion Passed: UID should remain after clear
Assertion Passed: Count after destroy
Assertion Passed: Keys after destroy

=== [v2.0] Starting Regression Tests ===
=== [v2.0] Testing destroy() isolation ===
Assertion Passed: [v2.0] dict1 should work before destroy
Assertion Passed: [v2.0] dict2 should work before destroy
Assertion Passed: [v2.0] dict2 should still work after dict1.destroy()
Assertion Passed: [v2.0] dict2.hasKey() should still work after dict1.destroy()
Assertion Passed: [v2.0] dict2 can add new items after dict1.destroy()
=== [v2.0] destroy() isolation test completed ===
=== [v2.0] Testing multiple instances independence ===
Assertion Passed: [v2.0] dict1 stores its own value
Assertion Passed: [v2.0] dict2 stores its own value
Assertion Passed: [v2.0] dict3 stores its own value
Assertion Passed: [v2.0] dict3 unaffected by dict1/dict2 destroy
=== [v2.0] multiple instances independence test completed ===

=== Starting Performance Tests ===

Performance Results:
Dictionary: 355ms (50000 ops)
Native Object: 164ms (50000 ops)
Performance ratio: 2.16463414634146x

=== All Tests Completed ===
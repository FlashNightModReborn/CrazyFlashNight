# AS2 类 *Allocator*

## 描述

一个非常简单的AS2内存空间管理方案。Allocator提供了：

  - 简单、统一的动态管理方案，避免了全局变量和索引数组的大量使用造成的混乱；

  - 基于数组索引的资源索引方案，保持了获取资源的高效与准确，同时让外层逻辑可以更灵活地实现。

  - 对已释放的对象，其在内存池中的索引位置会保留在Allocator内部，并在下次新对象的分配中被使用。这避免了在高频申请/释放资源的情景中，资源索引开销爆炸式增长的问题。

同时，Allocator没有提供：

  - 内置的内存池。Allocator使用时需要手动传入空数组，作为Allocator管理的对象；AS2的数组作为引用传递，所以你可以直接访问和操控原数组对象；

  - 对于存储对象的构造和析构方案。你需要手动构造完对象后，将其传入Allocator对象进行管理，防止由错误的默认行为而导致的错误。

## 构造函数

### `function Allocator(_pool: Array)`

*_pool*
将作为内存池被该Allocator管理的Array类型对象。必须是空数组。AS2中数组参数将作为引用传递，因此传入的数组仍然可以被外部访问和修改。

构造一个Allocator对象，并使其使用_pool作为内部的内存池。

#### 示例1

~~~TypeScript

var resources: Array = new Array();
var alloc: Allocator = new Allocator(resources);
// 你可以通过alloc对内存池resources进行操作，但resources仍然是正常变量，因此也可以在外界对其进行正常操作。
// 事实上，通过Allocator给出的索引直接访问resources是更推荐的访问对象方案。

~~~

## 方法

### `function Alloc(ref: Object): Number`

*ref*
将要放入Allocator中管理的对象。**注意！** 若传入的ref对象为Object或Array类型，则此时ref将作为引用传入。见示例2.1、示例2.2.

*返回值*
该对象在内存池中的索引。为Number类型。

将ref对象置于Allocator的管理中。ref可以是临时new出来的对象，也可以是已有的对象。见示例2.2.

#### 示例2.1

~~~TypeScript

var resources: Array = new Array();
var alloc: Allocator = new Allocator(resources);

var obj1 = new Object();
obj1.test = "shit";
trace(obj1.test);                           // 输出：shit

var index_obj: Number = alloc.Alloc(obj1);  // 将obj1对象移至Allocator下管理
trace(obj1.test);                           // 输出：shit

resources[index_obj].test = "fuck";         // 此时resources是Array，index_obj是Number，这一操作为数组访问，时间开销远小于索引数组/Object对象。
trace(resources[index_obj].test);           // 输出：fuck
trace(obj1.test);                           // 输出：fuck
                                            // 因为Alloc()时传入的参数obj1是Object类型，所以本质上resources[index_obj]和obj1指向的是同一个对象，可以进行修改。

var index_str: Number = alloc.Alloc(obj1.test);
trace(resources[index_str]);                // 输出：fuck
resources[index_str] = "shit, fuck";
trace(obj1.test);                           // 输出：fuck
trace(resources[index_str]);                // 输出：shit, fuck
                                            // 因为Alloc()时传入的参数obj1.test是String类型，所以此时Allocator在其空间中管理的是复制了obj1.test值的新String对象，所以修改其中一者与另一者并无任何关系。

                                            // Allocator管理的对象是否是引用，只与传入的参数是否（严格）是Array或Object类型有关。

~~~

#### 示例2.2

~~~TypeScript

var res: Array = new Array();
var alloct: Allocator = new Allocator(res);

var arr: Array = new Array(1, 2, 3);
var index_arr: Number = alloct.Alloc(arr);
trace(res[index_arr]);                      // 输出：1, 2, 3

arr[1] = "oh! my!";                         // 传入的是Array对象，故可以直接对原对象进行修改
trace(res[index_arr]);                      // 输出：1, oh! my!, 3

var index_arr2: Number = alloct.Alloc(new Array(3, 2, 1));
trace(res[index_arr2]);                     // 输出：3, 2, 1

res[index_arr2][2] = "ah! boom";            // 传入的是临时构造的对象，只能通过索引访问内存池进行修改
trace(res[index_arr2]);                     // 输出：3, 2, ah! boom

~~~

### `function Free(index: Number): Void`

*index*
将要释放的对象在Allocator中指定的索引。

释放该Allocator中index所指向的对象的存储空间。释放后，数组内index索引的对象将变成null. 若index指向的对象不存在（为undefined或null），则不执行任何操作。

#### 示例3

~~~TypeScript

var res: Array = new Array();
var alloct: Allocator = new Allocator(res);

var index: Number = alloct.Alloc(12);
trace(res[index]);                          // 输出：12

alloct.Free(index);
trace(res[index]);                          // 输出：null
trace(res[11]);                             // 输出：undefined
                                            // res[index]是曾经存储过对象，此处已经被释放的位置，res[11]是从未储存过对象的位置。前者的值为null，后者的值为undefined，这是不一样的。

alloct.Free(index);                         // 什么也不会发生，这是内存安全的

~~~

### `function FreeAll(): Void`

删除所有管理的对象，清理内存池。相比手动Free()所有储存的对象，FreeAll()不需要检查每个对象的具体情况，性能有极其显著的优势。

## 潜在案例分析：子弹池的内存管理

子弹是频繁申请/释放的对象的典型案例，使用Allocator可以大大节省子弹对象的索引开销。

### 原方案的性能分析

闪客快打7原有的子弹索引机制为，为每个子弹生成一个随机数x，将每个子弹命名为"子弹x"后存入当前世界的对象。设当前世界对象的变量为gameworld，则我们在：
   
- 指定访问时通过gameworld.子弹x的方式进行索引；
   
- 遍历时通过for (var 子弹索引 in gameworld)进行索引。
   
可以看出，以上方式采用随机数+索引数组的方法存储子弹，不仅有命名冲突的潜在风险，索引数组的访问也大大慢于普通数组。

### 使用Array而非Object的优化方案性能分析

如果保留随机数的索引方案，改用一般的子弹池数组bulletPool: Array（而不是利用Object对象作为索引数组）存储，也会有性能上的开销。

- 指定访问时，由于数组的索引并非稠密而是完全随机，那么基于AS2 Array对象的内部实现会有：在使用最“正统”的数组定义的情况下，未存有对象的索引位置仍然会占有内存空间，造成空间上的极大开销；在AS2针对非稠密索引做了优化的情况下，也至少会有额外一层索引映射的时间开销。

- 遍历时，若通过for (var i = 0; i < bulletPool.length; i++)的方式遍历，会有大量的i是不可用的，占用了大量时间；若通过for (var index in bulletPool)，则经过测试，在数据量较大时，这种非稠密的数组采用for...in遍历，效率大大低于稠密数组采用一般for遍历。

可以看出，虽然并不像原方案一样拥抱了每个可能的额外开销，成功达成了最坏的情况，使用Array而非Object的方案仍然有一些缺点。

### 使用Allocator的优化方案性能分析

我们使用Allocator管理子弹池数组，每个子弹在内存池中拥有索引，并且整个内存池内，Allocator的机制可以保证索引尽可能地连续、稠密。

- 指定访问时，由于数组是连续且稠密的，最坏情况下的时间空间开销，都不会低于其他方案的最好情况。

- 遍历时，可以使用一般的for遍历，并且不可用的i数量是尽可能小的，这远比for...in的方案要更优。

### 使用Allocator的开销

Allocator给予了用户在访问资源和遍历一系列资源时的较高性能，以及逻辑上的清晰、管理上的方便。但是Allocator的机制决定了它在Alloc()和Free()时产生的额外开销是不可避免的。我们需要辨别当前的情景是否适合使用Allocator进行资源的管理。

在目前，子弹池的内存管理是较为适合使用Allocator的，因为：

1. 子弹生成和消失时的常数开销本身就比较大（因为要生成和删除庞大的MovieClip对象），此时附加上一个Alloc()和Free()的开销不会显著改变性能瓶颈。

2. 对于子弹对象，相互之间的遍历所占用的性能，要远远超过子弹生成和消失所需要的性能，所以初步可以判断性能瓶颈在遍历上，而非生成/消失上，此时使用Allocator，理论上初步来讲，是会降低内存和空间开销的。

所以，Allocator适合使用的场景是大规模、性能瓶颈为遍历的场合。在小规模的应用上，Allocator相对于裸数组的额外开销并不可观，也可以基于实际情况考虑使用。

除此之外，正确使用FreeAll()也可以节省使用Allocator的开销。如，在子弹池的案例中，在过图时清空场上的子弹不需要遍历资源池挨个Free()，只需要使用FreeAll()方法即可。（和直接删除原有资源池和Allocator对象几乎没有差别）
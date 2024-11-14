/*
---
#### 1. Class Overview
`FrameTaskMinHeap` has been upgraded to a 4-ary heap structure to improve task scheduling performance. Additionally, by manually inlining private methods, we've reduced the number of function calls and minimized array indexing operations, further enhancing performance.
---
*/
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.FrameTaskMinHeap {
    private var heap:Array;                     // Stores frame indices in the 4-ary heap array
    private var frameMap:Object;                // Maps frame indices to task linked lists
    private var frameIndexToHeapIndex:Object;   // Maps frame indices to indices in the heap
    public var currentFrame:Number;             // Tracks the current frame number
    private var nodePool:Array;                 // Reusable pool of TaskIDNode instances
    private var poolSize:Number;                // Current number of nodes in the node pool
    private var heapSize:Number;                // Current size of the heap

    // Constructor: initializes the 4-ary heap and related structures
    public function FrameTaskMinHeap() {
        this.heap = [];
        this.frameMap = {};
        this.frameIndexToHeapIndex = {};
        this.currentFrame = 0;
        this.nodePool = [];
        this.poolSize = 0;
        this.heapSize = 0;                      // Initialize the heap size

        // Manually inlined initializeNodePool(128);
        for (var i:Number = 0; i < 128; i++) {
            this.nodePool[this.poolSize++] = new TaskIDNode(null);  // Initialize without specifying a task ID
        }
    }

    // Query the size of the node pool
    public function getNodePoolSize():Number {
        return this.poolSize;
    }

    // Fill the node pool by adding a specified number of idle nodes
    public function fillNodePool(size:Number):Void {
        for (var i:Number = 0; i < size; i++) {
            this.nodePool[this.poolSize++] = new TaskIDNode(null);  // Add empty nodes
        }
    }

    // Reduce the size of the node pool
    public function trimNodePool(size:Number):Void {
        if (this.poolSize > size) {
            this.poolSize = size;  // Directly adjust the size of the pool
        }
    }

    // Schedule the execution of a new task after a specified delay
    public function insert(taskID:String, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;  // Calculate the target frame index
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize++] = frameIndex;       // Insert using heapSize

            var heapIndex:Number = this.heapSize - 1;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Manually inlined bubbleUp(heapIndex);
            var currentIndex:Number = heapIndex;
            var currentValue:Number = this.heap[currentIndex];

            while (currentIndex > 0) {
                var parentIndex:Number = (currentIndex - 1) >> 2;  // Equivalent to Math.floor((currentIndex - 1) / 4)
                var parentValue:Number = this.heap[parentIndex];

                if (currentValue < parentValue) {
                    // Swap using temporary variables to reduce array accesses
                    this.heap[currentIndex] = parentValue;
                    this.heap[parentIndex] = currentValue;

                    // Update frameIndexToHeapIndex mapping
                    this.frameIndexToHeapIndex[currentValue] = parentIndex;
                    this.frameIndexToHeapIndex[parentValue] = currentIndex;

                    // Update index to continue bubbling up
                    currentIndex = parentIndex;
                    currentValue = this.heap[currentIndex];
                } else {
                    break;
                }
            }
        }

        // Manually inlined getNode(taskID);
        var newNode:TaskIDNode;
        if (this.poolSize > 0) {
            newNode = TaskIDNode(this.nodePool[--this.poolSize]);
            newNode.reset(taskID);  // Reinitialize the node's task ID
        } else {
            newNode = new TaskIDNode(taskID);  // Create a new node if the pool is empty
        }

        // Manually inlined insertNode(node, delay);
        newNode.slotIndex = frameIndex;                   // Store the frame index in the node
        this.frameMap[frameIndex].appendNode(newNode);    // Add the node to the linked list
    }

    // Directly insert an existing node and schedule it after a specified delay
    public function insertNode(node:TaskIDNode, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize++] = frameIndex;       // Insert using heapSize

            var heapIndex:Number = this.heapSize - 1;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Manually inlined bubbleUp(heapIndex);
            var currentIndex:Number = heapIndex;
            var currentValue:Number = this.heap[currentIndex];

            while (currentIndex > 0) {
                var parentIndex:Number = (currentIndex - 1) >> 2;
                var parentValue:Number = this.heap[parentIndex];

                if (currentValue < parentValue) {
                    this.heap[currentIndex] = parentValue;
                    this.heap[parentIndex] = currentValue;

                    this.frameIndexToHeapIndex[currentValue] = parentIndex;
                    this.frameIndexToHeapIndex[parentValue] = currentIndex;

                    currentIndex = parentIndex;
                    currentValue = this.heap[currentIndex];
                } else {
                    break;
                }
            }
        }
        node.slotIndex = frameIndex;
        this.frameMap[frameIndex].appendNode(node);
    }

    // Add a timer by task ID, creating a new node
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        // Manually inlined getNode(taskID);
        var node:TaskIDNode;
        if (this.poolSize > 0) {
            node = TaskIDNode(this.nodePool[--this.poolSize]);
            node.reset(taskID);  // Reinitialize the node's task ID
        } else {
            node = new TaskIDNode(taskID);  // Create a new node if the pool is empty
        }

        // Manually inlined insertNode(node, delay);
        var frameIndex:Number = this.currentFrame + delay;  // Calculate the target frame index
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize++] = frameIndex;       // Insert using heapSize

            var heapIndex:Number = this.heapSize - 1;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Manually inlined bubbleUp(heapIndex);
            var currentIndex:Number = heapIndex;
            var currentValue:Number = this.heap[currentIndex];

            while (currentIndex > 0) {
                var parentIndex:Number = (currentIndex - 1) >> 2;  // Equivalent to Math.floor((currentIndex - 1) / 4)
                var parentValue:Number = this.heap[parentIndex];

                if (currentValue < parentValue) {
                    // Swap using temporary variables to reduce array accesses
                    this.heap[currentIndex] = parentValue;
                    this.heap[parentIndex] = currentValue;

                    // Update frameIndexToHeapIndex mapping
                    this.frameIndexToHeapIndex[currentValue] = parentIndex;
                    this.frameIndexToHeapIndex[parentValue] = currentIndex;

                    // Update index to continue bubbling up
                    currentIndex = parentIndex;
                    currentValue = this.heap[currentIndex];
                } else {
                    break;
                }
            }
        }

        node.slotIndex = frameIndex;                   // Store the frame index in the node
        this.frameMap[frameIndex].appendNode(node);    // Add the node to the linked list

        return node;
    }

    // Directly add a timer using a node
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        // Manually inlined insertNode(node, delay);
        var frameIndex:Number = this.currentFrame + delay;
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize++] = frameIndex;       // Insert using heapSize

            var heapIndex:Number = this.heapSize - 1;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Manually inlined bubbleUp(heapIndex);
            var currentIndex:Number = heapIndex;
            var currentValue:Number = this.heap[currentIndex];

            while (currentIndex > 0) {
                var parentIndex:Number = (currentIndex - 1) >> 2;
                var parentValue:Number = this.heap[parentIndex];

                if (currentValue < parentValue) {
                    this.heap[currentIndex] = parentValue;
                    this.heap[parentIndex] = currentValue;

                    this.frameIndexToHeapIndex[currentValue] = parentIndex;
                    this.frameIndexToHeapIndex[parentValue] = currentIndex;

                    currentIndex = parentIndex;
                    currentValue = this.heap[currentIndex];
                } else {
                    break;
                }
            }
        }
        node.slotIndex = frameIndex;
        this.frameMap[frameIndex].appendNode(node);

        return node;
    }

    // Remove a task from the scheduling system by task ID
    public function removeById(taskID:String):Void {
        var node:TaskIDNode = findNodeById(taskID);
        if (node != null) {
            // Manually inlined removeNode(node);
            var frameIndex:Number = node.slotIndex;
            var list:TaskIDLinkedList = this.frameMap[frameIndex];
            list.remove(node);
            if (list.getFirst() == null) {  // Check if the linked list is empty
                var heapIndex:Number = this.frameIndexToHeapIndex[frameIndex];
                var lastIndex:Number = this.heapSize - 1;
                if (heapIndex != lastIndex) {
                    // Cache the values to reduce array indexing
                    var valueAtHeapIndex:Number = this.heap[heapIndex];
                    var valueAtLastIndex:Number = this.heap[lastIndex];

                    // Swap using temporary variables to reduce array accesses
                    this.heap[heapIndex] = valueAtLastIndex;
                    this.heap[lastIndex] = valueAtHeapIndex;

                    // Update frameIndexToHeapIndex mapping
                    this.frameIndexToHeapIndex[valueAtLastIndex] = heapIndex;
                    this.frameIndexToHeapIndex[valueAtHeapIndex] = lastIndex;
                }
                // Cache the new heapSize
                var newHeapSize:Number = this.heapSize - 1;
                this.heapSize = newHeapSize;

                // Maintain the heap property by inlining bubbleDown and bubbleUp
                if (heapIndex < newHeapSize) {
                    // Manually inlined bubbleDown(heapIndex);
                    var currentIndex:Number = heapIndex;
                    var currentValue:Number = this.heap[currentIndex];
                    var heapSizeLocal:Number = this.heapSize;

                    while (true) {
                        var smallestIndex:Number = currentIndex;
                        var smallestValue:Number = currentValue;

                        for (var j:Number = 1; j <= 4; j++) {
                            var childIndex:Number = (currentIndex << 2) + j;
                            if (childIndex >= heapSizeLocal) break;

                            var childValue:Number = this.heap[childIndex];
                            if (childValue < smallestValue) {
                                smallestIndex = childIndex;
                                smallestValue = childValue;
                            }
                        }

                        if (smallestIndex != currentIndex) {
                            this.heap[currentIndex] = smallestValue;
                            this.heap[smallestIndex] = currentValue;

                            this.frameIndexToHeapIndex[smallestValue] = currentIndex;
                            this.frameIndexToHeapIndex[currentValue] = smallestIndex;

                            currentIndex = smallestIndex;
                            currentValue = this.heap[currentIndex];
                        } else {
                            break;
                        }
                    }

                    // Manually inlined bubbleUp(heapIndex);
                    currentIndex = heapIndex;
                    currentValue = this.heap[currentIndex];

                    while (currentIndex > 0) {
                        var parentIndex:Number = (currentIndex - 1) >> 2;
                        var parentValue:Number = this.heap[parentIndex];

                        if (currentValue < parentValue) {
                            this.heap[currentIndex] = parentValue;
                            this.heap[parentIndex] = currentValue;

                            this.frameIndexToHeapIndex[currentValue] = parentIndex;
                            this.frameIndexToHeapIndex[parentValue] = currentIndex;

                            currentIndex = parentIndex;
                            currentValue = this.heap[currentIndex];
                        } else {
                            break;
                        }
                    }
                }

                // Delete the mapping
                delete this.frameIndexToHeapIndex[frameIndex];

                // Manually inlined recycleNode(node);
                node.reset(null);  // Clear the task ID and other properties
                this.nodePool[this.poolSize++] = node;  // Add the node back to the pool

            } else {
                // Manually inlined recycleNode(node);
                node.reset(null);  // Clear the task ID and other properties
                this.nodePool[this.poolSize++] = node;  // Add the node back to the pool
            }
        }
    }
    // Directly remove a node from the scheduling system
    public function removeDirectly(node:TaskIDNode):Void {
        // Manually inlined removeNode(node);
        var frameIndex:Number = node.slotIndex;
        var list:TaskIDLinkedList = this.frameMap[frameIndex];
        list.remove(node);
        if (list.getFirst() == null) {  // Check if the linked list is empty
            var heapIndex:Number = this.frameIndexToHeapIndex[frameIndex];
            var lastIndex:Number = this.heapSize - 1;
            if (heapIndex != lastIndex) {
                // Cache the values to reduce array indexing
                var valueAtHeapIndex:Number = this.heap[heapIndex];
                var valueAtLastIndex:Number = this.heap[lastIndex];

                // Swap using temporary variables to reduce array accesses
                this.heap[heapIndex] = valueAtLastIndex;
                this.heap[lastIndex] = valueAtHeapIndex;

                // Update frameIndexToHeapIndex mapping
                this.frameIndexToHeapIndex[valueAtLastIndex] = heapIndex;
                this.frameIndexToHeapIndex[valueAtHeapIndex] = lastIndex;
            }
            // Cache the new heapSize
            var newHeapSize:Number = this.heapSize - 1;
            this.heapSize = newHeapSize;

            // Maintain the heap property by inlining bubbleDown and bubbleUp
            if (heapIndex < newHeapSize) {
                // Manually inlined bubbleDown(heapIndex);
                var currentIndex:Number = heapIndex;
                var currentValue:Number = this.heap[currentIndex];
                var heapSizeLocal:Number = this.heapSize;

                while (true) {
                    var smallestIndex:Number = currentIndex;
                    var smallestValue:Number = currentValue;

                    for (var j:Number = 1; j <= 4; j++) {
                        var childIndex:Number = (currentIndex << 2) + j;
                        if (childIndex >= heapSizeLocal) break;

                        var childValue:Number = this.heap[childIndex];
                        if (childValue < smallestValue) {
                            smallestIndex = childIndex;
                            smallestValue = childValue;
                        }
                    }

                    if (smallestIndex != currentIndex) {
                        this.heap[currentIndex] = smallestValue;
                        this.heap[smallestIndex] = currentValue;

                        this.frameIndexToHeapIndex[smallestValue] = currentIndex;
                        this.frameIndexToHeapIndex[currentValue] = smallestIndex;

                        currentIndex = smallestIndex;
                        currentValue = this.heap[currentIndex];
                    } else {
                        break;
                    }
                }

                // Manually inlined bubbleUp(heapIndex);
                currentIndex = heapIndex;
                currentValue = this.heap[currentIndex];

                while (currentIndex > 0) {
                    var parentIndex:Number = (currentIndex - 1) >> 2;
                    var parentValue:Number = this.heap[parentIndex];

                    if (currentValue < parentValue) {
                        this.heap[currentIndex] = parentValue;
                        this.heap[parentIndex] = currentValue;

                        this.frameIndexToHeapIndex[currentValue] = parentIndex;
                        this.frameIndexToHeapIndex[parentValue] = currentIndex;

                        currentIndex = parentIndex;
                        currentValue = this.heap[currentIndex];
                    } else {
                        break;
                    }
                }
            }

            // Delete the mapping
            delete this.frameIndexToHeapIndex[frameIndex];

            // Manually inlined recycleNode(node);
            node.reset(null);  // Clear the task ID and other properties
            this.nodePool[this.poolSize++] = node;  // Add the node back to the pool

        } else {
            // Manually inlined recycleNode(node);
            node.reset(null);  // Clear the task ID and other properties
            this.nodePool[this.poolSize++] = node;  // Add the node back to the pool
        }
    }

    // Search across all scheduled tasks for a node with the specified task ID
    public function findNodeById(taskID:String):TaskIDNode {
        for (var i:Number = 0; i < this.heapSize; i++) {
            var frameIndex:Number = this.heap[i];
            var list:TaskIDLinkedList = this.frameMap[frameIndex];
            var currentNode:TaskIDNode = list.getFirst();
            while (currentNode != null) {
                if (currentNode.taskID == taskID) {
                    return currentNode;
                }
                currentNode = currentNode.next;
            }
        }
        return null;
    }

    // Reschedule an existing task based on a new delay
    public function rescheduleTimerByID(taskID:String, newDelay:Number):Void {
        var node:TaskIDNode = findNodeById(taskID);
        if (node != null) {
            // Manually inlined removeNode(node);
            var frameIndex:Number = node.slotIndex;
            var list:TaskIDLinkedList = this.frameMap[frameIndex];
            list.remove(node);
            if (list.getFirst() == null) {  // Check if the linked list is empty
                var heapIndex:Number = this.frameIndexToHeapIndex[frameIndex];
                var lastIndex:Number = this.heapSize - 1;
                if (heapIndex != lastIndex) {
                    // Cache the values to reduce array indexing
                    var valueAtHeapIndex:Number = this.heap[heapIndex];
                    var valueAtLastIndex:Number = this.heap[lastIndex];

                    // Swap using temporary variables to reduce array accesses
                    this.heap[heapIndex] = valueAtLastIndex;
                    this.heap[lastIndex] = valueAtHeapIndex;

                    // Update frameIndexToHeapIndex mapping
                    this.frameIndexToHeapIndex[valueAtLastIndex] = heapIndex;
                    this.frameIndexToHeapIndex[valueAtHeapIndex] = lastIndex;
                }
                // Cache the new heapSize
                var newHeapSize:Number = this.heapSize - 1;
                this.heapSize = newHeapSize;

                // Maintain the heap property by inlining bubbleDown and bubbleUp
                if (heapIndex < newHeapSize) {
                    // Manually inlined bubbleDown(heapIndex);
                    var currentIndex:Number = heapIndex;
                    var currentValue:Number = this.heap[currentIndex];
                    var heapSizeLocal:Number = this.heapSize;

                    while (true) {
                        var smallestIndex:Number = currentIndex;
                        var smallestValue:Number = currentValue;

                        for (var j:Number = 1; j <= 4; j++) {
                            var childIndex:Number = (currentIndex << 2) + j;
                            if (childIndex >= heapSizeLocal) break;

                            var childValue:Number = this.heap[childIndex];
                            if (childValue < smallestValue) {
                                smallestIndex = childIndex;
                                smallestValue = childValue;
                            }
                        }

                        if (smallestIndex != currentIndex) {
                            this.heap[currentIndex] = smallestValue;
                            this.heap[smallestIndex] = currentValue;

                            this.frameIndexToHeapIndex[smallestValue] = currentIndex;
                            this.frameIndexToHeapIndex[currentValue] = smallestIndex;

                            currentIndex = smallestIndex;
                            currentValue = this.heap[currentIndex];
                        } else {
                            break;
                        }
                    }

                    // Manually inlined bubbleUp(heapIndex);
                    currentIndex = heapIndex;
                    currentValue = this.heap[currentIndex];

                    while (currentIndex > 0) {
                        var parentIndex:Number = (currentIndex - 1) >> 2;
                        var parentValue:Number = this.heap[parentIndex];

                        if (currentValue < parentValue) {
                            this.heap[currentIndex] = parentValue;
                            this.heap[parentIndex] = currentValue;

                            this.frameIndexToHeapIndex[currentValue] = parentIndex;
                            this.frameIndexToHeapIndex[parentValue] = currentIndex;

                            currentIndex = parentIndex;
                            currentValue = this.heap[currentIndex];
                        } else {
                            break;
                        }
                    }
                }

                // Delete the mapping
                delete this.frameIndexToHeapIndex[frameIndex];

                // Manually inlined recycleNode(node);
                node.reset(null);  // Clear the task ID and other properties
                this.nodePool[this.poolSize++] = node;  // Add the node back to the pool

            } else {
                // Manually inlined recycleNode(node);
                node.reset(null);  // Clear the task ID and other properties
                this.nodePool[this.poolSize++] = node;  // Add the node back to the pool
            }

            // Manually inlined insertNode(node, newDelay);
            var newFrameIndex:Number = this.currentFrame + newDelay;
            if (!this.frameMap[newFrameIndex]) {
                this.frameMap[newFrameIndex] = new TaskIDLinkedList();
                this.heap[this.heapSize++] = newFrameIndex;       // Insert using heapSize

                var newHeapIndex:Number = this.heapSize - 1;
                this.frameIndexToHeapIndex[newFrameIndex] = newHeapIndex;

                // Manually inlined bubbleUp(newHeapIndex);
                var currentIndexNew:Number = newHeapIndex;
                var currentValueNew:Number = this.heap[currentIndexNew];

                while (currentIndexNew > 0) {
                    var parentIndexNew:Number = (currentIndexNew - 1) >> 2;
                    var parentValueNew:Number = this.heap[parentIndexNew];

                    if (currentValueNew < parentValueNew) {
                        this.heap[currentIndexNew] = parentValueNew;
                        this.heap[parentIndexNew] = currentValueNew;

                        this.frameIndexToHeapIndex[currentValueNew] = parentIndexNew;
                        this.frameIndexToHeapIndex[parentValueNew] = currentIndexNew;

                        currentIndexNew = parentIndexNew;
                        currentValueNew = this.heap[currentIndexNew];
                    } else {
                        break;
                    }
                }
            }
            node.slotIndex = newFrameIndex;
            this.frameMap[newFrameIndex].appendNode(node);
        }
    }
    // Reschedule a task by moving the node to a new delay
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        if (node != null) {
            // Manually inlined removeNode(node);
            var frameIndex:Number = node.slotIndex;
            var list:TaskIDLinkedList = this.frameMap[frameIndex];
            list.remove(node);
            if (list.getFirst() == null) {  // Check if the linked list is empty
                var heapIndex:Number = this.frameIndexToHeapIndex[frameIndex];
                var lastIndex:Number = this.heapSize - 1;
                if (heapIndex != lastIndex) {
                    // Cache the values to reduce array indexing
                    var valueAtHeapIndex:Number = this.heap[heapIndex];
                    var valueAtLastIndex:Number = this.heap[lastIndex];

                    // Swap using temporary variables to reduce array accesses
                    this.heap[heapIndex] = valueAtLastIndex;
                    this.heap[lastIndex] = valueAtHeapIndex;

                    // Update frameIndexToHeapIndex mapping
                    this.frameIndexToHeapIndex[valueAtLastIndex] = heapIndex;
                    this.frameIndexToHeapIndex[valueAtHeapIndex] = lastIndex;
                }
                // Cache the new heapSize
                var newHeapSize:Number = this.heapSize - 1;
                this.heapSize = newHeapSize;

                // Maintain the heap property by inlining bubbleDown and bubbleUp
                if (heapIndex < newHeapSize) {
                    // Manually inlined bubbleDown(heapIndex);
                    var currentIndex:Number = heapIndex;
                    var currentValue:Number = this.heap[currentIndex];
                    var heapSizeLocal:Number = this.heapSize;

                    while (true) {
                        var smallestIndex:Number = currentIndex;
                        var smallestValue:Number = currentValue;

                        for (var j:Number = 1; j <= 4; j++) {
                            var childIndex:Number = (currentIndex << 2) + j;
                            if (childIndex >= heapSizeLocal) break;

                            var childValue:Number = this.heap[childIndex];
                            if (childValue < smallestValue) {
                                smallestIndex = childIndex;
                                smallestValue = childValue;
                            }
                        }

                        if (smallestIndex != currentIndex) {
                            this.heap[currentIndex] = smallestValue;
                            this.heap[smallestIndex] = currentValue;

                            this.frameIndexToHeapIndex[smallestValue] = currentIndex;
                            this.frameIndexToHeapIndex[currentValue] = smallestIndex;

                            currentIndex = smallestIndex;
                            currentValue = this.heap[currentIndex];
                        } else {
                            break;
                        }
                    }

                    // Manually inlined bubbleUp(heapIndex);
                    currentIndex = heapIndex;
                    currentValue = this.heap[currentIndex];

                    while (currentIndex > 0) {
                        var parentIndex:Number = (currentIndex - 1) >> 2;
                        var parentValue:Number = this.heap[parentIndex];

                        if (currentValue < parentValue) {
                            this.heap[currentIndex] = parentValue;
                            this.heap[parentIndex] = currentValue;

                            this.frameIndexToHeapIndex[currentValue] = parentIndex;
                            this.frameIndexToHeapIndex[parentValue] = currentIndex;

                            currentIndex = parentIndex;
                            currentValue = this.heap[currentIndex];
                        } else {
                            break;
                        }
                    }
                }

                // Delete the mapping
                delete this.frameIndexToHeapIndex[frameIndex];

                // Manually inlined recycleNode(node);
                node.reset(null);  // Clear the task ID and other properties
                this.nodePool[this.poolSize++] = node;  // Add the node back to the pool

            } else {
                // Manually inlined recycleNode(node);
                node.reset(null);  // Clear the task ID and other properties
                this.nodePool[this.poolSize++] = node;  // Add the node back to the pool
            }

            // Manually inlined insertNode(node, newDelay);
            var newFrameIndex:Number = this.currentFrame + newDelay;
            if (!this.frameMap[newFrameIndex]) {
                this.frameMap[newFrameIndex] = new TaskIDLinkedList();
                this.heap[this.heapSize++] = newFrameIndex;       // Insert using heapSize

                var newHeapIndex:Number = this.heapSize - 1;
                this.frameIndexToHeapIndex[newFrameIndex] = newHeapIndex;

                // Manually inlined bubbleUp(newHeapIndex);
                var currentIndexNew:Number = newHeapIndex;
                var currentValueNew:Number = this.heap[currentIndexNew];

                while (currentIndexNew > 0) {
                    var parentIndexNew:Number = (currentIndexNew - 1) >> 2;
                    var parentValueNew:Number = this.heap[parentIndexNew];

                    if (currentValueNew < parentValueNew) {
                        this.heap[currentIndexNew] = parentValueNew;
                        this.heap[parentIndexNew] = currentValueNew;

                        this.frameIndexToHeapIndex[currentValueNew] = parentIndexNew;
                        this.frameIndexToHeapIndex[parentValueNew] = currentIndexNew;

                        currentIndexNew = parentIndexNew;
                        currentValueNew = this.heap[currentIndexNew];
                    } else {
                        break;
                    }
                }
            }
            node.slotIndex = newFrameIndex;
            this.frameMap[newFrameIndex].appendNode(node);
        }
    }
    // Process due tasks and advance the frame count
    public function tick():TaskIDLinkedList {
        this.currentFrame++;
        if (this.heapSize > 0 && this.heap[0] <= this.currentFrame) {
            return extractTasksAtMinFrame();
        }
        return null;
    }

    // Peek at the tasks at the earliest frame without removing them
    public function peekMin():Object {
        if (this.heapSize == 0) return null;
        var heapZero:Number = this.heap[0];
        return {frame: heapZero, tasks: this.frameMap[heapZero]};
    }

    // Extract and remove tasks at the earliest frame
    public function extractTasksAtMinFrame():TaskIDLinkedList {
        if (this.heapSize == 0) return null;
        var minFrame:Number = this.heap[0];
        var lastIndex:Number = this.heapSize - 1;
        if (lastIndex > 0) {
            // Cache the values to reduce array indexing
            var valueAt0:Number = this.heap[0];
            var valueAtLast:Number = this.heap[lastIndex];

            // Swap using temporary variables to reduce array accesses
            this.heap[0] = valueAtLast;
            this.heap[lastIndex] = valueAt0;

            // Update frameIndexToHeapIndex mapping
            this.frameIndexToHeapIndex[valueAtLast] = 0;
            this.frameIndexToHeapIndex[valueAt0] = lastIndex;
        }
        // Cache the new heapSize
        var newHeapSize:Number = this.heapSize - 1;
        this.heapSize = newHeapSize;

        if (newHeapSize > 0) {
            // Manually inlined bubbleDown(0);
            var currentIndex:Number = 0;
            var currentValue:Number = this.heap[currentIndex];
            var heapSizeLocal:Number = this.heapSize;

            while (true) {
                var smallestIndex:Number = currentIndex;
                var smallestValue:Number = currentValue;

                for (var j:Number = 1; j <= 4; j++) {
                    var childIndex:Number = (currentIndex << 2) + j;
                    if (childIndex >= heapSizeLocal) break;

                    var childValue:Number = this.heap[childIndex];
                    if (childValue < smallestValue) {
                        smallestIndex = childIndex;
                        smallestValue = childValue;
                    }
                }

                if (smallestIndex != currentIndex) {
                    this.heap[currentIndex] = smallestValue;
                    this.heap[smallestIndex] = currentValue;

                    this.frameIndexToHeapIndex[smallestValue] = currentIndex;
                    this.frameIndexToHeapIndex[currentValue] = smallestIndex;

                    currentIndex = smallestIndex;
                    currentValue = this.heap[currentIndex];
                } else {
                    break;
                }
            }
        }

        var tasks:TaskIDLinkedList = this.frameMap[minFrame];
        delete this.frameMap[minFrame];
        return tasks;
    }
}

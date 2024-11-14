/*
---
#### 1. Class Overview
`FrameTaskMinHeap` has been upgraded to a 4-ary heap structure to improve task scheduling performance. By applying loop unrolling and logic branch optimizations similar to those in `TaskMinHeap`, we've further enhanced performance by reducing the overhead of loop iterations and conditional checks during heap operations.
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

    // D is hardcoded as 4, representing a 4-ary heap (each node can have up to 4 children)

    /**
     * Constructor: initializes the 4-ary heap and related structures
     */
    public function FrameTaskMinHeap() {
        this.heap = new Array(128); // Preallocate heap array to improve performance
        this.frameMap = {};
        this.frameIndexToHeapIndex = {};
        this.currentFrame = 0;
        this.nodePool = [];
        this.poolSize = 0;
        this.heapSize = 0;

        // Preallocate node pool with 128 nodes
        for (var i:Number = 0; i < 128; i++) {
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
        }
    }

    // Query the size of the node pool
    public function getNodePoolSize():Number {
        return this.poolSize;
    }

    // Fill the node pool by adding a specified number of idle nodes
    public function fillNodePool(size:Number):Void {
        for (var i:Number = 0; i < size; i++) {
            this.nodePool[this.poolSize++] = new TaskIDNode(null);
        }
    }

    // Reduce the size of the node pool
    public function trimNodePool(size:Number):Void {
        if (this.poolSize > size) {
            this.poolSize = size;
        }
    }

    // Schedule the execution of a new task after a specified delay
    public function insert(taskID:String, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize] = frameIndex;
            var heapIndex:Number = this.heapSize;
            this.heapSize++;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Inline bubbleUp with loop unrolling and logic branch optimization
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2; // parentIndex = floor((currentIndex - 1) / 4)
                parentValue = this.heap[parentIndex];

                if (currentValue >= parentValue) {
                    break; // Current node is in the correct position
                }

                // Swap current node with parent node
                this.heap[currentIndex] = parentValue;
                this.frameIndexToHeapIndex[parentValue] = currentIndex;
                currentIndex = parentIndex;
            }

            this.heap[currentIndex] = currentValue;
            this.frameIndexToHeapIndex[currentValue] = currentIndex;
        }

        // Get a node from the node pool
        var newNode:TaskIDNode;
        if (this.poolSize > 0) {
            newNode = TaskIDNode(this.nodePool[--this.poolSize]);
            newNode.reset(taskID);
        } else {
            newNode = new TaskIDNode(taskID);
        }

        // Insert the node
        newNode.slotIndex = frameIndex;
        this.frameMap[frameIndex].appendNode(newNode);
    }

    // Directly insert an existing node and schedule it after a specified delay
    public function insertNode(node:TaskIDNode, delay:Number):Void {
        var frameIndex:Number = this.currentFrame + delay;
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize] = frameIndex;
            var heapIndex:Number = this.heapSize;
            this.heapSize++;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Inline bubbleUp with loop unrolling and logic branch optimization
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2;
                parentValue = this.heap[parentIndex];

                if (currentValue >= parentValue) {
                    break;
                }

                // Swap current node with parent node
                this.heap[currentIndex] = parentValue;
                this.frameIndexToHeapIndex[parentValue] = currentIndex;
                currentIndex = parentIndex;
            }

            this.heap[currentIndex] = currentValue;
            this.frameIndexToHeapIndex[currentValue] = currentIndex;
        }

        node.slotIndex = frameIndex;
        this.frameMap[frameIndex].appendNode(node);
    }

    // Add a timer by task ID, creating a new node
    public function addTimerByID(taskID:String, delay:Number):TaskIDNode {
        var node:TaskIDNode;
        if (this.poolSize > 0) {
            node = TaskIDNode(this.nodePool[--this.poolSize]);
            node.reset(taskID);
        } else {
            node = new TaskIDNode(taskID);
        }

        // Insert the node
        var frameIndex:Number = this.currentFrame + delay;
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize] = frameIndex;
            var heapIndex:Number = this.heapSize;
            this.heapSize++;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Inline bubbleUp with loop unrolling and logic branch optimization
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2;
                parentValue = this.heap[parentIndex];

                if (currentValue >= parentValue) {
                    break;
                }

                // Swap current node with parent node
                this.heap[currentIndex] = parentValue;
                this.frameIndexToHeapIndex[parentValue] = currentIndex;
                currentIndex = parentIndex;
            }

            this.heap[currentIndex] = currentValue;
            this.frameIndexToHeapIndex[currentValue] = currentIndex;
        }

        node.slotIndex = frameIndex;
        this.frameMap[frameIndex].appendNode(node);

        return node;
    }

    // Directly add a timer using a node
    public function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode {
        var frameIndex:Number = this.currentFrame + delay;
        if (!this.frameMap[frameIndex]) {
            this.frameMap[frameIndex] = new TaskIDLinkedList();
            this.heap[this.heapSize] = frameIndex;
            var heapIndex:Number = this.heapSize;
            this.heapSize++;
            this.frameIndexToHeapIndex[frameIndex] = heapIndex;

            // Inline bubbleUp with loop unrolling and logic branch optimization
            var currentIndex:Number = heapIndex;
            var currentValue:Number = frameIndex;

            var parentIndex:Number;
            var parentValue:Number;

            while (currentIndex > 0) {
                parentIndex = (currentIndex - 1) >> 2;
                parentValue = this.heap[parentIndex];

                if (currentValue >= parentValue) {
                    break;
                }

                // Swap current node with parent node
                this.heap[currentIndex] = parentValue;
                this.frameIndexToHeapIndex[parentValue] = currentIndex;
                currentIndex = parentIndex;
            }

            this.heap[currentIndex] = currentValue;
            this.frameIndexToHeapIndex[currentValue] = currentIndex;
        }

        node.slotIndex = frameIndex;
        this.frameMap[frameIndex].appendNode(node);

        return node;
    }

    // Remove a task from the scheduling system by task ID
    public function removeById(taskID:String):Void {
        var node:TaskIDNode = findNodeById(taskID);
        if (node != null) {
            removeNode(node);
        }
    }

    // Directly remove a node from the scheduling system
    public function removeDirectly(node:TaskIDNode):Void {
        removeNode(node);
    }

    // Core method to remove a node, handling linked list and heap updates
    public function removeNode(node:TaskIDNode):Void {
        var frameIndex:Number = node.slotIndex;
        var list:TaskIDLinkedList = this.frameMap[frameIndex];
        list.remove(node);

        if (list.getFirst() == null) {
            // No more tasks at this frame index, remove from heap
            var heapIndex:Number = this.frameIndexToHeapIndex[frameIndex];
            var lastIndex:Number = --this.heapSize;
            var lastValue:Number = this.heap[lastIndex];

            if (heapIndex != lastIndex) {
                this.heap[heapIndex] = lastValue;
                this.frameIndexToHeapIndex[lastValue] = heapIndex;
            }

            // Remove last element reference
            this.heap[lastIndex] = null;
            delete this.frameIndexToHeapIndex[frameIndex];

            if (heapIndex < this.heapSize) {
                // Rebalance the heap
                // Inline bubbleDown with loop unrolling and logic branch optimization
                var currentIndex:Number = heapIndex;
                var currentValue:Number = this.heap[currentIndex];

                var minIndex:Number;
                var baseChildIndex:Number;
                var remaining:Number;
                var childIndex:Number;
                var childValue:Number;
                var minValue:Number;

                while (true) {
                    minIndex = currentIndex;
                    baseChildIndex = (currentIndex << 2);
                    remaining = this.heapSize - baseChildIndex;

                    minValue = currentValue;

                    if (remaining >= 4) {
                        // 4 children
                        childIndex = baseChildIndex + 1;

                        // Compare first child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare second child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare third child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare fourth child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else if (remaining == 3) {
                        // 3 children
                        childIndex = baseChildIndex + 1;

                        // Compare first child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare second child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare third child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else if (remaining == 2) {
                        // 2 children
                        childIndex = baseChildIndex + 1;

                        // Compare first child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare second child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else if (remaining == 1) {
                        // 1 child
                        childIndex = baseChildIndex + 1;

                        // Compare the only child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else {
                        // No children
                        break;
                    }

                    if (minIndex == currentIndex) {
                        break;
                    }

                    // Swap current node with the smallest child
                    this.heap[currentIndex] = minValue;
                    this.frameIndexToHeapIndex[minValue] = currentIndex;
                    currentIndex = minIndex;
                    currentValue = this.heap[currentIndex];
                }

                this.heap[currentIndex] = currentValue;
                this.frameIndexToHeapIndex[currentValue] = currentIndex;
            }

            delete this.frameMap[frameIndex];
        }

        // Recycle the node
        node.reset(null);
        this.nodePool[this.poolSize++] = node;
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
            removeNode(node);
            node.reset(taskID);
            insertNode(node, newDelay);
        }
    }

    // Reschedule a task by moving the node to a new delay
    public function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void {
        if (node != null) {
            removeNode(node);
            insertNode(node, newDelay);
        }
    }

    // Process due tasks and advance the frame count
    public function tick():TaskIDLinkedList {
        if (this.heapSize > 0 and this.heap[0] <= ++this.currentFrame) {
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
        var lastIndex:Number = --this.heapSize;
        var lastValue:Number = this.heap[lastIndex];

        if (lastIndex >= 0) {
            this.heap[0] = lastValue;
            this.frameIndexToHeapIndex[lastValue] = 0;
            this.heap[lastIndex] = null;
            delete this.frameIndexToHeapIndex[minFrame];

            if (this.heapSize > 0) {
                // Rebalance the heap
                var currentIndex:Number = 0;
                var currentValue:Number = this.heap[currentIndex];

                var minIndex:Number;
                var baseChildIndex:Number;
                var remaining:Number;
                var childIndex:Number;
                var childValue:Number;
                var minValue:Number;

                while (true) {
                    minIndex = currentIndex;
                    baseChildIndex = (currentIndex << 2);
                    remaining = this.heapSize - baseChildIndex;

                    minValue = currentValue;

                    if (remaining >= 4) {
                        // 4 children
                        childIndex = baseChildIndex + 1;

                        // Compare first child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare second child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare third child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare fourth child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else if (remaining == 3) {
                        // 3 children
                        childIndex = baseChildIndex + 1;

                        // Compare first child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare second child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare third child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else if (remaining == 2) {
                        // 2 children
                        childIndex = baseChildIndex + 1;

                        // Compare first child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }

                        // Compare second child
                        childValue = this.heap[++childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else if (remaining == 1) {
                        // 1 child
                        childIndex = baseChildIndex + 1;

                        // Compare the only child
                        childValue = this.heap[childIndex];
                        if (childValue < minValue) {
                            minIndex = childIndex;
                            minValue = childValue;
                        }
                    } else {
                        // No children
                        break;
                    }

                    if (minIndex == currentIndex) {
                        break;
                    }

                    // Swap current node with the smallest child
                    this.heap[currentIndex] = minValue;
                    this.frameIndexToHeapIndex[minValue] = currentIndex;
                    currentIndex = minIndex;
                    currentValue = this.heap[currentIndex];
                }

                this.heap[currentIndex] = currentValue;
                this.frameIndexToHeapIndex[currentValue] = currentIndex;
            }
        }

        var tasks:TaskIDLinkedList = this.frameMap[minFrame];
        delete this.frameMap[minFrame];
        return tasks;
    }
}

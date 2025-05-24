class Allocator
{
    private var pool: Array;
    private var availSpace: Array;

    // precondition: _pool is an empty array
    public function Allocator(_pool: Array)
    {
        this.pool = _pool;
        this.availSpace = new Array();
    }

    public function Alloc(ref: Object): Number
    {
        if (this.availSpace.length > 0)
        {
            var index = Number(this.availSpace.pop());
            this.pool[index] = ref;
            return index;
        }
        else
        {
            this.pool.push(ref);
            return this.pool.length - 1;
        }
    }
    public function Free(index: Number): Void
    {
        if ((this.pool[index] == null) || (this.pool[index] == undefined))
        {
            return;
        }
        
        delete this.pool[index];
        this.pool[index] = null;
        this.availSpace.push(index);
    }
    public function FreeAll(): Void
    {
        delete this.pool;
        delete this.availSpace;
        this.pool = new Array();
        this.availSpace = new Array();
    }
}
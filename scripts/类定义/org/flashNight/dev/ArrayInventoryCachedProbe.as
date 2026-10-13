import org.flashNight.arki.item.itemCollection.*;

/** Ideal read cache ablation. Only supported API writes occur in the experiment. */
class org.flashNight.dev.ArrayInventoryCachedProbe extends org.flashNight.dev.ArrayInventoryTreeBaseline {
    private var probeRevision:Number;
    private var probeIndexes:Array;
    public function ArrayInventoryCachedProbe(initial:Object, slotCapacity:Number) {
        super(initial, slotCapacity);
        probeRevision = -1;
    }
    private function getProbeIndexes():Array {
        var revision:Number = getMutationRevision();
        if (probeIndexes == null || probeRevision != revision) {
            probeIndexes = super.getIndexes();
            probeRevision = revision;
        }
        return probeIndexes;
    }
    public function getIndexes():Array {
        return getProbeIndexes().concat();
    }
    public function getItemArray():Array{
        var indexArr:Array = getProbeIndexes();
        var list = [];
        for(var i = 0; i<indexArr.length; i++){
            list.push(this.items[indexArr[i]]);
        }
        return list;
    }
    public function searchFirstKey(name:String):String {
        if(name == null || name == undefined || name == "") return undefined;
        var indexArr:Array = getProbeIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index:Number = Number(indexArr[i]);
            var item:Object = this.items[index];
            if(item != null && item.name == name) return String(index);
        }
        return undefined;
    }
    public function getFirstVacancy():Number {
        var indexArr:Array = getProbeIndexes();
        var currentVacancy:Number = 0;  // 当前要检查的索引

        for(var i:Number = 0; i < indexArr.length; i++){
            var occupiedIndex:Number = Number(indexArr[i]);
            if (occupiedIndex > currentVacancy) {
                return currentVacancy < this.capacity ? currentVacancy : -1;
            }
            currentVacancy = occupiedIndex + 1;
            if(currentVacancy >= this.capacity) return -1;
        }

        return currentVacancy < this.capacity ? currentVacancy : -1;
    }
    public function getVacancies(amount:Number):Array {
        if (isNaN(amount)) amount = 16;
        var vacancies:Array = [];
        var currentVacancy:Number = 0;  // 当前要检查的索引
        var indexArr:Array = getProbeIndexes();

        // 遍历已占用的位置并寻找空位
        for (var i:Number = 0; i < indexArr.length && vacancies.length < amount; i++) {
            var occupiedIndex:Number = Number(indexArr[i]);

            // 如果当前占用位置大于当前检查的位置，则计算空位区间
            if (occupiedIndex > currentVacancy) {
                // 批量添加从 currentVacancy 到 occupiedIndex - 1 的空位
                var spacesToAdd:Number = Math.min(occupiedIndex - currentVacancy, amount - vacancies.length);
                for (var j:Number = 0; j < spacesToAdd; j++) {
                    if(currentVacancy >= this.capacity) return vacancies;
                    vacancies.push(currentVacancy++);
                }
            }

            // 跳过已占用的当前索引
            currentVacancy = occupiedIndex + 1;
            if(currentVacancy >= this.capacity) return vacancies;
        }

        // 如果没有填满数量，继续添加剩余的空位直到容量为止
        while (vacancies.length < amount && currentVacancy < this.capacity) {
            vacancies.push(currentVacancy++);
        }

        return vacancies;
    }
    public function find(callback:Function) {
        if(typeof callback !== "function") return null;
        var indexArr:Array = getProbeIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index:Number = Number(indexArr[i]);
            var item:Object = this.items[index];
            if(callback(item)) return item;
        }
        return null;
    }
    public function findIndex(callback:Function):Number {
        if(typeof callback !== "function") return -1;
        var indexArr:Array = getProbeIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index:Number = Number(indexArr[i]);
            var item:Object = this.items[index];
            if(callback(item)) return index;
        }
        return -1;
    }
}

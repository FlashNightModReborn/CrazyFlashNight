_root.敌人函数.被击移动 = function(移动方向, 速度, 摩擦力) {
    if (this.免疫击退)
        return;
    this.移动钝感硬直(_root.钝感硬直时间);
    this.减速度 = 摩擦力;
    this.speed = 速度;
    this.onEnterFrame = function() {
        if (!this.硬直中) {
            this.speed -= this.减速度;
            if (this.speed <= 0) {
                delete this.onEnterFrame;
                return;
            }
            this.移动(移动方向, this.speed);
        }
    };
};

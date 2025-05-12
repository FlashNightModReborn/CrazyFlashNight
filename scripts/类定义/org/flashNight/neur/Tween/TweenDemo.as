import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

/**
 * TweenDemo - 演示补间动画库的基本功能
 * 
 */
class org.flashNight.neur.Tween.TweenDemo {
    // 舞台引用
    private var _root:MovieClip;
    
    // UI元素
    private var _container:MovieClip;
    private var _redSquare:MovieClip;
    private var _blueCircle:MovieClip;
    private var _greenTriangle:MovieClip;
    private var _controlPanel:MovieClip;
    
    /**
     * 构造函数 - 设置示例并初始化UI
     */
    public function TweenDemo(root:MovieClip) {
        // 保存舞台引用
        _root = root;
        

        
        // 创建容器
        _container = _root.createEmptyMovieClip("container_mc", _root.getNextHighestDepth());
        _container._x = 275;
        _container._y = 200;
        
        // 创建形状
        createShapes();
        
        // 创建控制面板
        createControlPanel();
        
        // 初始动画
        Tween.delayedCall(0.5, playIntroAnimation, []);
    }
    
    /**
     * 创建演示用的形状
     */
    private function createShapes():Void {
        // 红色方块
        _redSquare = _container.createEmptyMovieClip("redSquare_mc", _container.getNextHighestDepth());
        with (_redSquare) {
            beginFill(0xFF0000, 100);
            moveTo(-25, -25);
            lineTo(25, -25);
            lineTo(25, 25);
            lineTo(-25, 25);
            lineTo(-25, -25);
            endFill();
            _x = -150;
            _y = 0;
            _alpha = 0;
        }
        
        // 蓝色圆形
        _blueCircle = _container.createEmptyMovieClip("blueCircle_mc", _container.getNextHighestDepth());
        with (_blueCircle) {
            beginFill(0x0066FF, 100);
            moveTo(0, -30);
            curveTo(30, -30, 30, 0);
            curveTo(30, 30, 0, 30);
            curveTo(-30, 30, -30, 0);
            curveTo(-30, -30, 0, -30);
            endFill();
            _x = 0;
            _y = 0;
            _alpha = 0;
        }
        
        // 绿色三角形
        _greenTriangle = _container.createEmptyMovieClip("greenTriangle_mc", _container.getNextHighestDepth());
        with (_greenTriangle) {
            beginFill(0x00CC00, 100);
            moveTo(0, -30);
            lineTo(35, 30);
            lineTo(-35, 30);
            lineTo(0, -30);
            endFill();
            _x = 150;
            _y = 0;
            _alpha = 0;
        }
    }
    
    /**
     * 创建控制面板和按钮
     */
    private function createControlPanel():Void {
        _controlPanel = _root.createEmptyMovieClip("controlPanel_mc", _root.getNextHighestDepth());
        _controlPanel._y = 350;
        
        // 背景
        with (_controlPanel) {
            beginFill(0xEEEEEE, 50);
            moveTo(0, 0);
            lineTo(550, 0);
            lineTo(550, 100);
            lineTo(0, 100);
            lineTo(0, 0);
            endFill();
        }
        
        // 创建按钮
        createButton("简单动画", 50, 25, playBasicAnimation);
        createButton("弹性效果", 175, 25, playElasticAnimation);
        createButton("回弹效果", 300, 25, playBackAnimation);
        createButton("弹跳效果", 425, 25, playBounceAnimation);
        
        createButton("淡入动画", 50, 75, playFadeInAnimation);
        createButton("连续动画", 175, 75, playSequentialAnimation);
        createButton("重置", 300, 75, resetShapes);
        createButton("全部动画", 425, 75, playAllAnimations);
    }
    
    /**
     * 创建一个按钮
     */
    private function createButton(label:String, x:Number, y:Number, callback:Function):MovieClip {
        var btn:MovieClip = _controlPanel.createEmptyMovieClip("btn_" + label, _controlPanel.getNextHighestDepth());
        btn._x = x;
        btn._y = y;
        
        // 按钮背景
        with (btn) {
            beginFill(0x666666, 100);
            moveTo(0, 0);
            lineTo(100, 0);
            lineTo(100, 30);
            lineTo(0, 30);
            lineTo(0, 0);
            endFill();
        }
        
        // 文本标签
        var txtFormat:TextFormat = new TextFormat();
        txtFormat.font = "Arial";
        txtFormat.size = 12;
        txtFormat.color = 0xFFFFFF;
        txtFormat.align = "center";
        
        var txt:TextField = btn.createTextField("label_txt", btn.getNextHighestDepth(), 0, 5, 100, 20);
        txt.text = label;
        txt.setTextFormat(txtFormat);
        txt.selectable = false;
        
        // 点击事件
        btn.onRelease = callback;
        
        return btn;
    }
    
    /**
     * 动画：初始动画
     */
    private function playIntroAnimation():Void {

        
        // 初始位置调整
        _redSquare._y = -100;
        _blueCircle._y = -100;
        _greenTriangle._y = -100;
        
        // 红色方块动画
        Tween.to(_redSquare, 1, {
            _y: 0, 
            _alpha: 100, 
            ease: Easing.Back.easeOut
        });
        
        // 蓝色圆形动画（延迟0.2秒）
        Tween.delayedCall(0.2, function():Void {
            Tween.to(_blueCircle, 1, {
                _y: 0, 
                _alpha: 100, 
                ease: Easing.Back.easeOut
            });
        });
        
        // 绿色三角形动画（延迟0.4秒）
        Tween.delayedCall(0.4, function():Void {
            Tween.to(_greenTriangle, 1, {
                _y: 0, 
                _alpha: 100, 
                ease: Easing.Back.easeOut
            });
        });
    }
    
    /**
     * 动画：基本动画
     */
    private function playBasicAnimation():Void {
        resetShapes();
        

        
        // 红色方块：移动和旋转
        Tween.to(_redSquare, 1, {
            _x: -150,
            _y: 50,
            _rotation: 45,
            _alpha: 100,
            ease: Easing.Quad.easeInOut
        });
        
        // 蓝色圆形：缩放
        Tween.to(_blueCircle, 1, {
            _xscale: 150,
            _yscale: 150,
            _alpha: 100,
            ease: Easing.Quad.easeInOut
        });
        
        // 绿色三角形：旋转
        Tween.to(_greenTriangle, 1, {
            _rotation: 180,
            _alpha: 100,
            ease: Easing.Quad.easeInOut
        });
    }
    
    /**
     * 动画：弹性效果
     */
    private function playElasticAnimation():Void {
        resetShapes();
        

        
        // 设置初始位置
        _redSquare._x = -350;
        _blueCircle._x = -350;
        _greenTriangle._x = -350;
        _redSquare._alpha = 100;
        _blueCircle._alpha = 100;
        _greenTriangle._alpha = 100;
        
        // 红色方块
        Tween.to(_redSquare, 2, {
            _x: -150,
            ease: Easing.Elastic.easeOut
        });
        
        // 蓝色圆形（延迟0.2秒）
        Tween.delayedCall(0.2, function():Void {
            Tween.to(_blueCircle, 2, {
                _x: 0,
                ease: Easing.Elastic.easeOut
            });
        });
        
        // 绿色三角形（延迟0.4秒）
        Tween.delayedCall(0.4, function():Void {
            Tween.to(_greenTriangle, 2, {
                _x: 150,
                ease: Easing.Elastic.easeOut
            });
        });
    }
    
    /**
     * 动画：回弹效果
     */
    private function playBackAnimation():Void {
        resetShapes();
        

        
        // 设置初始位置
        _redSquare._y = -200;
        _blueCircle._y = -200;
        _greenTriangle._y = -200;
        _redSquare._alpha = 100;
        _blueCircle._alpha = 100;
        _greenTriangle._alpha = 100;
        
        // 红色方块
        Tween.to(_redSquare, 1.5, {
            _y: 0,
            ease: Easing.Back.easeOut
        });
        
        // 蓝色圆形（延迟0.2秒）
        Tween.delayedCall(0.2, function():Void {
            Tween.to(_blueCircle, 1.5, {
                _y: 0,
                ease: Easing.Back.easeOut
            });
        });
        
        // 绿色三角形（延迟0.4秒）
        Tween.delayedCall(0.4, function():Void {
            Tween.to(_greenTriangle, 1.5, {
                _y: 0,
                ease: Easing.Back.easeOut
            });
        });
    }
    
    /**
     * 动画：弹跳效果
     */
    private function playBounceAnimation():Void {
        resetShapes();
        

        
        // 设置初始位置
        _redSquare._y = -200;
        _blueCircle._y = -200;
        _greenTriangle._y = -200;
        _redSquare._alpha = 100;
        _blueCircle._alpha = 100;
        _greenTriangle._alpha = 100;
        
        // 红色方块
        Tween.to(_redSquare, 1.5, {
            _y: 0,
            ease: Easing.Bounce.easeOut
        });
        
        // 蓝色圆形（延迟0.2秒）
        Tween.delayedCall(0.2, function():Void {
            Tween.to(_blueCircle, 1.5, {
                _y: 0,
                ease: Easing.Bounce.easeOut
            });
        });
        
        // 绿色三角形（延迟0.4秒）
        Tween.delayedCall(0.4, function():Void {
            Tween.to(_greenTriangle, 1.5, {
                _y: 0,
                ease: Easing.Bounce.easeOut
            });
        });
    }
    
    /**
     * 动画：淡入效果
     */
    private function playFadeInAnimation():Void {
        resetShapes();
        

        
        // 淡入方块
        Tween.from(_redSquare, 1, {
            _alpha: 0,
            _xscale: 0,
            _yscale: 0,
            ease: Easing.Cubic.easeOut
        });
        
        // 淡入圆形
        Tween.from(_blueCircle, 1, {
            _alpha: 0,
            _xscale: 0,
            _yscale: 0,
            ease: Easing.Cubic.easeOut
        });
        
        // 淡入三角形
        Tween.from(_greenTriangle, 1, {
            _alpha: 0,
            _xscale: 0,
            _yscale: 0,
            ease: Easing.Cubic.easeOut
        });
    }
    
    /**
     * 动画：连续动画
     */
    private function playSequentialAnimation():Void {
        resetShapes();
        

        
        // 设置初始值
        _redSquare._alpha = 100;
        _blueCircle._alpha = 0;
        _greenTriangle._alpha = 0;
        
        // 红色方块：旋转
        Tween.to(_redSquare, 1, {
            _rotation: 360,
            onComplete: function():Void {
                // 蓝色圆形：淡入并缩放
                Tween.to(_blueCircle, 1, {
                    _alpha: 100, 
                    _xscale: 150,
                    _yscale: 150,
                    ease: Easing.Back.easeOut,
                    onComplete: function():Void {
                        // 绿色三角形：淡入并旋转
                        Tween.to(_greenTriangle, 1, {
                            _alpha: 100,
                            _rotation: 180,
                            ease: Easing.Elastic.easeOut
                        });
                    }
                });
            }
        });
    }
    
    /**
     * 动画：全部动画演示
     */
    private function playAllAnimations():Void {
        resetShapes();
        

        
        // 初始状态
        _redSquare._alpha = 0;
        _blueCircle._alpha = 0;
        _greenTriangle._alpha = 0;
        
        // 第1步：淡入所有形状
        Tween.to(_redSquare, 0.8, {
            _alpha: 100,
            ease: Easing.Quad.easeIn
        });
        
        Tween.to(_blueCircle, 0.8, {
            _alpha: 100,
            ease: Easing.Quad.easeIn
        });
        
        Tween.to(_greenTriangle, 0.8, {
            _alpha: 100,
            ease: Easing.Quad.easeIn,
            onComplete: function():Void {
                // 第2步：向上移动
                Tween.to(_redSquare, 0.8, {
                    _y: -50,
                    ease: Easing.Back.easeOut
                });
                
                Tween.to(_blueCircle, 0.8, {
                    _y: -50,
                    ease: Easing.Back.easeOut
                });
                
                Tween.to(_greenTriangle, 0.8, {
                    _y: -50,
                    ease: Easing.Back.easeOut,
                    onComplete: function():Void {
                        // 第3步：旋转
                        Tween.to(_redSquare, 1, {
                            _rotation: 360,
                            ease: Easing.Quad.easeInOut
                        });
                        
                        Tween.to(_blueCircle, 1, {
                            _rotation: 360,
                            ease: Easing.Quad.easeInOut
                        });
                        
                        Tween.to(_greenTriangle, 1, {
                            _rotation: 360,
                            ease: Easing.Quad.easeInOut,
                            onComplete: function():Void {
                                // 第4步：弹回原位
                                Tween.to(_redSquare, 1.2, {
                                    _y: 0,
                                    ease: Easing.Elastic.easeOut
                                });
                                
                                Tween.to(_blueCircle, 1.2, {
                                    _y: 0,
                                    ease: Easing.Elastic.easeOut
                                });
                                
                                Tween.to(_greenTriangle, 1.2, {
                                    _y: 0,
                                    ease: Easing.Elastic.easeOut
                                });
                            }
                        });
                    }
                });
            }
        });
    }
    
    /**
     * 重置所有形状到初始状态
     */
    private function resetShapes():Void {
        
        Tween.killTweensOf(_redSquare);
        Tween.killTweensOf(_blueCircle);
        Tween.killTweensOf(_greenTriangle);
        
        // 重置位置和属性
        _redSquare._x = -150;
        _redSquare._y = 0;
        _redSquare._rotation = 0;
        _redSquare._xscale = 100;
        _redSquare._yscale = 100;
        _redSquare._alpha = 0;
        
        _blueCircle._x = 0;
        _blueCircle._y = 0;
        _blueCircle._rotation = 0;
        _blueCircle._xscale = 100;
        _blueCircle._yscale = 100;
        _blueCircle._alpha = 0;
        
        _greenTriangle._x = 150;
        _greenTriangle._y = 0;
        _greenTriangle._rotation = 0;
        _greenTriangle._xscale = 100;
        _greenTriangle._yscale = 100;
        _greenTriangle._alpha = 0;
    }
}
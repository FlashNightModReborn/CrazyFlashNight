org.flashNight.neur.Event.LifecycleEventDispatcherTest.runAllTests();





=== Running LifecycleEventDispatcher Tests ===

-- testBasicLifecycle --
[ASSERTION PASSED]: Dispatcher should not be destroyed initially
[ASSERTION PASSED]: Target should be correctly set
[ASSERTION PASSED]: Bidirectional reference should be established
[ASSERTION PASSED]: EventDispatcher functionality should work
监听器已移除：HID1
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: Dispatcher should be destroyed after destroy() call
[ASSERTION PASSED]: Target reference should be cleared
-- testBasicLifecycle Completed --


-- testEventBridging --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: subscribeTargetEvent should return valid ID
[ASSERTION PASSED]: subscribeTargetEvent should return valid ID
[ASSERTION PASSED]: Target events should be triggered
目标对象的所有自定义事件监听器已 禁用。
[ASSERTION PASSED]: Events should be disabled
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Events should be re-enabled
监听器已移除：HID4
所有监听器已移除：onPress，已恢复原生处理器。
[ASSERTION PASSED]: Unsubscribed event should not trigger
[ASSERTION PASSED]: Should show 2 remaining events (onRelease, onUnload)
[ASSERTION PASSED]: Should show 2 remaining handlers
[ASSERTION PASSED]: onRelease event should have exactly 1 handler
监听器已移除：HID3
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID5
所有监听器已移除：onRelease，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
-- testEventBridging Completed --


-- testDestroyAndCleanup --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Events should work before destroy
监听器已移除：HID7
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID8
所有监听器已移除：onPress，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Dispatcher should be auto-destroyed on target unload
Warning: publish called on a destroyed EventDispatcher.
[ASSERTION PASSED]: Events should not work after destroy
[ASSERTION PASSED]: Multiple destroy calls should be safe
-- testDestroyAndCleanup Completed --


-- testBasicTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Old target should work before transfer
监听器已移除：HID10
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Transfer should return ID mapping
[ASSERTION PASSED]: Target should be updated after transfer
[ASSERTION PASSED]: New target should have correct dispatcher reference
[ASSERTION PASSED]: Old target reference should be cleared
[ASSERTION PASSED]: New target should work after transfer
[ASSERTION PASSED]: Old target should be cleaned after transfer
监听器已移除：HID16
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID15
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID14
所有监听器已移除：onRelease，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
onUnload 已执行并清理所有事件监听器。
[ASSERTION PASSED]: Lifecycle should be transferred to new target
-- testBasicTransfer Completed --


-- testTransferModes --
自动清理及用户卸载逻辑已设置。
监听器已移除：HID18
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Specific events should be transferred
[ASSERTION PASSED]: Non-specific events should not be transferred
[ASSERTION PASSED]: Non-transferred events should remain on old target
用户的 onUnload 函数已更新。
监听器已移除：HID27
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 2 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Non-excluded events should be transferred
[ASSERTION PASSED]: Excluded events should not be transferred
监听器已移除：HID26
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID24
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID25
所有监听器已移除：onRelease，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID35
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID33
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID34
所有监听器已移除：onRelease，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
-- testTransferModes Completed --


-- testTransferWithEventStates --
自动清理及用户卸载逻辑已设置。
目标对象的所有自定义事件监听器已 禁用。
监听器已移除：HID37
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Disabled state should be transferred to new target
目标对象的所有自定义事件监听器已 启用。
[ASSERTION PASSED]: Events should work after enabling on new target
监听器已移除：HID41
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID40
所有监听器已移除：onPress，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
-- testTransferWithEventStates Completed --


-- testStaticTransferMethods --
自动清理及用户卸载逻辑已设置。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 2 个监听器
[ASSERTION PASSED]: Static transfer should return ID mapping
[ASSERTION PASSED]: Static transfer should work correctly
[ASSERTION PASSED]: Source should be cleared after static transfer
[ASSERTION PASSED]: Static transfer with null source should return null
监听器已移除：HID45
-- testStaticTransferMethods Completed --


-- testTransferEdgeCases --
[ASSERTION PASSED]: Transfer to same target should be handled gracefully
[ASSERTION PASSED]: Target should remain unchanged
[ASSERTION PASSED]: Transfer to null target should return null
监听器已移除：HID50
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: Transfer on destroyed dispatcher should return null
[ASSERTION PASSED]: Destroyed dispatcher should return empty stats
[ASSERTION PASSED]: Subscribe on destroyed dispatcher should return null
-- testTransferEdgeCases Completed --


-- testBossPhaseTransfer --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: Phase1 systems should work normally
[Boss] Phase1 → Phase2 transformation...
监听器已移除：HID52
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 4 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Phase1 to Phase2 transfer should succeed
[ASSERTION PASSED]: Phase2 should work, Phase1 should be cleaned
[Boss] Phase2 → Phase3 transformation...
监听器已移除：HID62
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
transferSpecificEventListeners 完成：已转移 3 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Phase3 critical systems should work
[ASSERTION PASSED]: Sound system should not be transferred in Phase3
[Boss] Boss defeated, cleaning up...
监听器已移除：HID67
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID64
所有监听器已移除：onEnterFrame，已恢复原生处理器。
监听器已移除：HID65
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID66
所有监听器已移除：onKeyDown，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: Boss dispatcher should be destroyed
-- testBossPhaseTransfer Completed --


-- testComplexTransferChain --
自动清理及用户卸载逻辑已设置。
[Chain] Transferring from target 0 to target 1
监听器已移除：HID69
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 0→1 should succeed
[ASSERTION PASSED]: Target 1 should work after transfer
[Chain] Transferring from target 1 to target 2
监听器已移除：HID73
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 1→2 should succeed
[ASSERTION PASSED]: Target 2 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[Chain] Transferring from target 2 to target 3
监听器已移除：HID76
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 2→3 should succeed
[ASSERTION PASSED]: Target 3 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[Chain] Transferring from target 3 to target 4
监听器已移除：HID79
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 1 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: Chain transfer 3→4 should succeed
[ASSERTION PASSED]: Target 4 should work after transfer
[ASSERTION PASSED]: Previous targets should be cleaned
[ASSERTION PASSED]: Final target should be targets[4]
[ASSERTION PASSED]: Final bidirectional reference should be correct
监听器已移除：HID82
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID81
所有监听器已移除：onPress，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
-- testComplexTransferChain Completed --


-- testTransferPerformance --
自动清理及用户卸载逻辑已设置。
[Transfer Performance] Registered 500 handlers in 22 ms
监听器已移除：HID84
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 500 个监听器
用户的 onUnload 函数已更新。
[Transfer Performance] Transferred 500 handlers in 7 ms
[ASSERTION PASSED]: All transferred handlers should work
监听器已移除：HID1086
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID586
监听器已移除：HID587
监听器已移除：HID588
监听器已移除：HID589
监听器已移除：HID590
监听器已移除：HID591
监听器已移除：HID592
监听器已移除：HID593
监听器已移除：HID594
监听器已移除：HID595
监听器已移除：HID596
监听器已移除：HID597
监听器已移除：HID598
监听器已移除：HID599
监听器已移除：HID600
监听器已移除：HID601
监听器已移除：HID602
监听器已移除：HID603
监听器已移除：HID604
监听器已移除：HID605
监听器已移除：HID606
监听器已移除：HID607
监听器已移除：HID608
监听器已移除：HID609
监听器已移除：HID610
监听器已移除：HID611
监听器已移除：HID612
监听器已移除：HID613
监听器已移除：HID614
监听器已移除：HID615
监听器已移除：HID616
监听器已移除：HID617
监听器已移除：HID618
监听器已移除：HID619
监听器已移除：HID620
监听器已移除：HID621
监听器已移除：HID622
监听器已移除：HID623
监听器已移除：HID624
监听器已移除：HID625
监听器已移除：HID626
监听器已移除：HID627
监听器已移除：HID628
监听器已移除：HID629
监听器已移除：HID630
监听器已移除：HID631
监听器已移除：HID632
监听器已移除：HID633
监听器已移除：HID634
监听器已移除：HID635
监听器已移除：HID636
监听器已移除：HID637
监听器已移除：HID638
监听器已移除：HID639
监听器已移除：HID640
监听器已移除：HID641
监听器已移除：HID642
监听器已移除：HID643
监听器已移除：HID644
监听器已移除：HID645
监听器已移除：HID646
监听器已移除：HID647
监听器已移除：HID648
监听器已移除：HID649
监听器已移除：HID650
监听器已移除：HID651
监听器已移除：HID652
监听器已移除：HID653
监听器已移除：HID654
监听器已移除：HID655
监听器已移除：HID656
监听器已移除：HID657
监听器已移除：HID658
监听器已移除：HID659
监听器已移除：HID660
监听器已移除：HID661
监听器已移除：HID662
监听器已移除：HID663
监听器已移除：HID664
监听器已移除：HID665
监听器已移除：HID666
监听器已移除：HID667
监听器已移除：HID668
监听器已移除：HID669
监听器已移除：HID670
监听器已移除：HID671
监听器已移除：HID672
监听器已移除：HID673
监听器已移除：HID674
监听器已移除：HID675
监听器已移除：HID676
监听器已移除：HID677
监听器已移除：HID678
监听器已移除：HID679
监听器已移除：HID680
监听器已移除：HID681
监听器已移除：HID682
监听器已移除：HID683
监听器已移除：HID684
监听器已移除：HID685
监听器已移除：HID686
监听器已移除：HID687
监听器已移除：HID688
监听器已移除：HID689
监听器已移除：HID690
监听器已移除：HID691
监听器已移除：HID692
监听器已移除：HID693
监听器已移除：HID694
监听器已移除：HID695
监听器已移除：HID696
监听器已移除：HID697
监听器已移除：HID698
监听器已移除：HID699
监听器已移除：HID700
监听器已移除：HID701
监听器已移除：HID702
监听器已移除：HID703
监听器已移除：HID704
监听器已移除：HID705
监听器已移除：HID706
监听器已移除：HID707
监听器已移除：HID708
监听器已移除：HID709
监听器已移除：HID710
监听器已移除：HID711
监听器已移除：HID712
监听器已移除：HID713
监听器已移除：HID714
监听器已移除：HID715
监听器已移除：HID716
监听器已移除：HID717
监听器已移除：HID718
监听器已移除：HID719
监听器已移除：HID720
监听器已移除：HID721
监听器已移除：HID722
监听器已移除：HID723
监听器已移除：HID724
监听器已移除：HID725
监听器已移除：HID726
监听器已移除：HID727
监听器已移除：HID728
监听器已移除：HID729
监听器已移除：HID730
监听器已移除：HID731
监听器已移除：HID732
监听器已移除：HID733
监听器已移除：HID734
监听器已移除：HID735
监听器已移除：HID736
监听器已移除：HID737
监听器已移除：HID738
监听器已移除：HID739
监听器已移除：HID740
监听器已移除：HID741
监听器已移除：HID742
监听器已移除：HID743
监听器已移除：HID744
监听器已移除：HID745
监听器已移除：HID746
监听器已移除：HID747
监听器已移除：HID748
监听器已移除：HID749
监听器已移除：HID750
监听器已移除：HID751
监听器已移除：HID752
监听器已移除：HID753
监听器已移除：HID754
监听器已移除：HID755
监听器已移除：HID756
监听器已移除：HID757
监听器已移除：HID758
监听器已移除：HID759
监听器已移除：HID760
监听器已移除：HID761
监听器已移除：HID762
监听器已移除：HID763
监听器已移除：HID764
监听器已移除：HID765
监听器已移除：HID766
监听器已移除：HID767
监听器已移除：HID768
监听器已移除：HID769
监听器已移除：HID770
监听器已移除：HID771
监听器已移除：HID772
监听器已移除：HID773
监听器已移除：HID774
监听器已移除：HID775
监听器已移除：HID776
监听器已移除：HID777
监听器已移除：HID778
监听器已移除：HID779
监听器已移除：HID780
监听器已移除：HID781
监听器已移除：HID782
监听器已移除：HID783
监听器已移除：HID784
监听器已移除：HID785
监听器已移除：HID786
监听器已移除：HID787
监听器已移除：HID788
监听器已移除：HID789
监听器已移除：HID790
监听器已移除：HID791
监听器已移除：HID792
监听器已移除：HID793
监听器已移除：HID794
监听器已移除：HID795
监听器已移除：HID796
监听器已移除：HID797
监听器已移除：HID798
监听器已移除：HID799
监听器已移除：HID800
监听器已移除：HID801
监听器已移除：HID802
监听器已移除：HID803
监听器已移除：HID804
监听器已移除：HID805
监听器已移除：HID806
监听器已移除：HID807
监听器已移除：HID808
监听器已移除：HID809
监听器已移除：HID810
监听器已移除：HID811
监听器已移除：HID812
监听器已移除：HID813
监听器已移除：HID814
监听器已移除：HID815
监听器已移除：HID816
监听器已移除：HID817
监听器已移除：HID818
监听器已移除：HID819
监听器已移除：HID820
监听器已移除：HID821
监听器已移除：HID822
监听器已移除：HID823
监听器已移除：HID824
监听器已移除：HID825
监听器已移除：HID826
监听器已移除：HID827
监听器已移除：HID828
监听器已移除：HID829
监听器已移除：HID830
监听器已移除：HID831
监听器已移除：HID832
监听器已移除：HID833
监听器已移除：HID834
监听器已移除：HID835
监听器已移除：HID836
监听器已移除：HID837
监听器已移除：HID838
监听器已移除：HID839
监听器已移除：HID840
监听器已移除：HID841
监听器已移除：HID842
监听器已移除：HID843
监听器已移除：HID844
监听器已移除：HID845
监听器已移除：HID846
监听器已移除：HID847
监听器已移除：HID848
监听器已移除：HID849
监听器已移除：HID850
监听器已移除：HID851
监听器已移除：HID852
监听器已移除：HID853
监听器已移除：HID854
监听器已移除：HID855
监听器已移除：HID856
监听器已移除：HID857
监听器已移除：HID858
监听器已移除：HID859
监听器已移除：HID860
监听器已移除：HID861
监听器已移除：HID862
监听器已移除：HID863
监听器已移除：HID864
监听器已移除：HID865
监听器已移除：HID866
监听器已移除：HID867
监听器已移除：HID868
监听器已移除：HID869
监听器已移除：HID870
监听器已移除：HID871
监听器已移除：HID872
监听器已移除：HID873
监听器已移除：HID874
监听器已移除：HID875
监听器已移除：HID876
监听器已移除：HID877
监听器已移除：HID878
监听器已移除：HID879
监听器已移除：HID880
监听器已移除：HID881
监听器已移除：HID882
监听器已移除：HID883
监听器已移除：HID884
监听器已移除：HID885
监听器已移除：HID886
监听器已移除：HID887
监听器已移除：HID888
监听器已移除：HID889
监听器已移除：HID890
监听器已移除：HID891
监听器已移除：HID892
监听器已移除：HID893
监听器已移除：HID894
监听器已移除：HID895
监听器已移除：HID896
监听器已移除：HID897
监听器已移除：HID898
监听器已移除：HID899
监听器已移除：HID900
监听器已移除：HID901
监听器已移除：HID902
监听器已移除：HID903
监听器已移除：HID904
监听器已移除：HID905
监听器已移除：HID906
监听器已移除：HID907
监听器已移除：HID908
监听器已移除：HID909
监听器已移除：HID910
监听器已移除：HID911
监听器已移除：HID912
监听器已移除：HID913
监听器已移除：HID914
监听器已移除：HID915
监听器已移除：HID916
监听器已移除：HID917
监听器已移除：HID918
监听器已移除：HID919
监听器已移除：HID920
监听器已移除：HID921
监听器已移除：HID922
监听器已移除：HID923
监听器已移除：HID924
监听器已移除：HID925
监听器已移除：HID926
监听器已移除：HID927
监听器已移除：HID928
监听器已移除：HID929
监听器已移除：HID930
监听器已移除：HID931
监听器已移除：HID932
监听器已移除：HID933
监听器已移除：HID934
监听器已移除：HID935
监听器已移除：HID936
监听器已移除：HID937
监听器已移除：HID938
监听器已移除：HID939
监听器已移除：HID940
监听器已移除：HID941
监听器已移除：HID942
监听器已移除：HID943
监听器已移除：HID944
监听器已移除：HID945
监听器已移除：HID946
监听器已移除：HID947
监听器已移除：HID948
监听器已移除：HID949
监听器已移除：HID950
监听器已移除：HID951
监听器已移除：HID952
监听器已移除：HID953
监听器已移除：HID954
监听器已移除：HID955
监听器已移除：HID956
监听器已移除：HID957
监听器已移除：HID958
监听器已移除：HID959
监听器已移除：HID960
监听器已移除：HID961
监听器已移除：HID962
监听器已移除：HID963
监听器已移除：HID964
监听器已移除：HID965
监听器已移除：HID966
监听器已移除：HID967
监听器已移除：HID968
监听器已移除：HID969
监听器已移除：HID970
监听器已移除：HID971
监听器已移除：HID972
监听器已移除：HID973
监听器已移除：HID974
监听器已移除：HID975
监听器已移除：HID976
监听器已移除：HID977
监听器已移除：HID978
监听器已移除：HID979
监听器已移除：HID980
监听器已移除：HID981
监听器已移除：HID982
监听器已移除：HID983
监听器已移除：HID984
监听器已移除：HID985
监听器已移除：HID986
监听器已移除：HID987
监听器已移除：HID988
监听器已移除：HID989
监听器已移除：HID990
监听器已移除：HID991
监听器已移除：HID992
监听器已移除：HID993
监听器已移除：HID994
监听器已移除：HID995
监听器已移除：HID996
监听器已移除：HID997
监听器已移除：HID998
监听器已移除：HID999
监听器已移除：HID1000
监听器已移除：HID1001
监听器已移除：HID1002
监听器已移除：HID1003
监听器已移除：HID1004
监听器已移除：HID1005
监听器已移除：HID1006
监听器已移除：HID1007
监听器已移除：HID1008
监听器已移除：HID1009
监听器已移除：HID1010
监听器已移除：HID1011
监听器已移除：HID1012
监听器已移除：HID1013
监听器已移除：HID1014
监听器已移除：HID1015
监听器已移除：HID1016
监听器已移除：HID1017
监听器已移除：HID1018
监听器已移除：HID1019
监听器已移除：HID1020
监听器已移除：HID1021
监听器已移除：HID1022
监听器已移除：HID1023
监听器已移除：HID1024
监听器已移除：HID1025
监听器已移除：HID1026
监听器已移除：HID1027
监听器已移除：HID1028
监听器已移除：HID1029
监听器已移除：HID1030
监听器已移除：HID1031
监听器已移除：HID1032
监听器已移除：HID1033
监听器已移除：HID1034
监听器已移除：HID1035
监听器已移除：HID1036
监听器已移除：HID1037
监听器已移除：HID1038
监听器已移除：HID1039
监听器已移除：HID1040
监听器已移除：HID1041
监听器已移除：HID1042
监听器已移除：HID1043
监听器已移除：HID1044
监听器已移除：HID1045
监听器已移除：HID1046
监听器已移除：HID1047
监听器已移除：HID1048
监听器已移除：HID1049
监听器已移除：HID1050
监听器已移除：HID1051
监听器已移除：HID1052
监听器已移除：HID1053
监听器已移除：HID1054
监听器已移除：HID1055
监听器已移除：HID1056
监听器已移除：HID1057
监听器已移除：HID1058
监听器已移除：HID1059
监听器已移除：HID1060
监听器已移除：HID1061
监听器已移除：HID1062
监听器已移除：HID1063
监听器已移除：HID1064
监听器已移除：HID1065
监听器已移除：HID1066
监听器已移除：HID1067
监听器已移除：HID1068
监听器已移除：HID1069
监听器已移除：HID1070
监听器已移除：HID1071
监听器已移除：HID1072
监听器已移除：HID1073
监听器已移除：HID1074
监听器已移除：HID1075
监听器已移除：HID1076
监听器已移除：HID1077
监听器已移除：HID1078
监听器已移除：HID1079
监听器已移除：HID1080
监听器已移除：HID1081
监听器已移除：HID1082
监听器已移除：HID1083
监听器已移除：HID1084
监听器已移除：HID1085
所有监听器已移除：onEnterFrame，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[Transfer Performance] Destroyed dispatcher in 60 ms
-- testTransferPerformance Completed --


-- [v2.3 I3] testHandlerTracking --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.3 I3] subscribeTargetEvent should return valid ID for onPress
[ASSERTION PASSED]: [v2.3 I3] subscribeTargetEvent should return valid ID for onRelease
[ASSERTION PASSED]: [v2.3 I3] External EventCoordinator.addEventListener should return valid ID
[ASSERTION PASSED]: [v2.3 I3] Dispatcher handlers should be called (count=2)
[ASSERTION PASSED]: [v2.3 I3] External handler should be called (count=1)
监听器已移除：HID1088
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID1089
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID1090
所有监听器已移除：onRelease，已恢复原生处理器。
[ASSERTION PASSED]: [v2.3 I3] Dispatcher handlers should be cleared after destroy
[ASSERTION PASSED]: [v2.3 I3] CRITICAL - External handler should still work after dispatcher.destroy()
监听器已移除：HID1091
所有监听器已移除：onRollOver，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: [v2.3 I3] External handler should be removed after manual cleanup
-- [v2.3 I3] testHandlerTracking Completed --


-- [v2.3.3] testTransferHandlerIDRemapping --
自动清理及用户卸载逻辑已设置。
[ASSERTION PASSED]: [v2.3.3] Old target handlers should work
监听器已移除：HID1093
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
自动清理及用户卸载逻辑已设置。
所有事件监听器已清除。
transferEventListeners：已清理旧对象的监听器
transferEventListeners 完成：已转移 3 个监听器
用户的 onUnload 函数已更新。
[ASSERTION PASSED]: [v2.3.3] Transfer should return valid idMap
[v2.3.3] ID mapping: HID1094 -> HID1100
[v2.3.3] ID mapping: HID1095 -> HID1099
[v2.3.3] ID mapping: HID1096 -> HID1098
[ASSERTION PASSED]: [v2.3.3] idMap should contain mappings (got 3)
[ASSERTION PASSED]: [v2.3.3] New target handlers should work after transfer
监听器已移除：HID1101
用户的 onUnload 函数已更新。
所有监听器已移除：onUnload，已恢复原生处理器。
监听器已移除：HID1100
所有监听器已移除：onPress，已恢复原生处理器。
监听器已移除：HID1099
所有监听器已移除：onRelease，已恢复原生处理器。
监听器已移除：HID1098
所有监听器已移除：onEnterFrame，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[ASSERTION PASSED]: [v2.3.3] Dispatcher should be destroyed
[ASSERTION PASSED]: [v2.3.3] CRITICAL - All handlers should be cleared after destroy() (press=0, release=0, enterFrame=0)
[ASSERTION PASSED]: [v2.3.3] No ghost callbacks should remain after destroy()
-- [v2.3.3] testTransferHandlerIDRemapping Completed --


=== LifecycleEventDispatcher Tests Completed ===
Total Assertions: 79
Passed Assertions: 79
Failed Assertions: 0


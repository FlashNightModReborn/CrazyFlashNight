param([int]$TimeoutSeconds = 300)
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId dog-form-storage -TemplateRelativePath 'scripts/test-runners/dog-form-storage/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/neur/Server/test/DogFormStorageProbeTest.as' -SuiteFqns 'org.flashNight.neur.Server.test.DogFormStorageProbeTest' -ExpectedTracePatterns @('DogFormStorageProbe ready') -SuccessSummary '犬种隔离存盘探针已编译就绪，落盘与跨进程读回另由驱动证明' -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE

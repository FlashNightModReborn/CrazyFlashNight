using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task<object> CheckRayLighting(string root,NativeCompositorSession session,string output,
        RayVisualDrawFrame ray,WorldLightComposer lights,WorldLightingPreset preset)
    {
        var originalGeometry=ray.Data.Take(ray.Count*RayVisualCatalog.Stride).ToArray();
        session.CombatFxAtlas(CombatFxCatalog.Load(root));
        await WaitFor(()=>session.CombatFxReady,session,"world lighting resources");
        session.SetLut(preset.LutSet.BlendLevel(0));session.ClearRayFrame();session.ClearCombatFxFrame();
        var dark=Grab(session,Path.Combine(output,"lighting-dark.png"));
        session.RayFrame(ray,0,0,1);
        var body=Grab(session,Path.Combine(output,"lighting-body-only.png"));
        lights.SetRays(ray);var selected=lights.Compose(0,0,1);
        Require(selected.LightCount==12,"Twelve primary styles should contribute twelve environment lights");
        session.CombatFxFrame(selected,0,0,1);
        var combined=Grab(session,Path.Combine(output,"lighting-combined.png"));
        Require(Changed(body,combined,new Rectangle(0,0,1024,576))>200,"Ray lighting did not change the world");
        session.ClearRayFrame();
        var environment=Grab(session,Path.Combine(output,"lighting-environment-only.png"));
        var coverage=new List<object>();
        for(int i=0;i<12;i++) {
            int pixels=Changed(dark,environment,new Rectangle(i%2*512,i/2*96,512,96));
            Require(pixels>8,"Ray style did not illuminate any material: "+RayVisualCatalog.Styles[i]);
            coverage.Add(new{style=RayVisualCatalog.Styles[i],materialPixels=pixels});
        }
        session.CombatFxFrame(lights.Compose(65,-25,.8f),65,-25,.8f);
        var moved=Grab(session,Path.Combine(output,"lighting-camera.png"));
        Require(Changed(environment,moved,new Rectangle(0,0,1024,576))>100,"Environment light ignored camera transform");
        lights.ClearRays();session.CombatFxFrame(lights.Compose(0,0,1),0,0,1);
        var cleared=Grab(session,Path.Combine(output,"lighting-cleared.png"));
        Require(Changed(dark,cleared,new Rectangle(0,0,1024,576))<4,"Cleared ray lights left illuminated material");
        Require(originalGeometry.SequenceEqual(ray.Data.Take(ray.Count*RayVisualCatalog.Stride)),
            "World lighting changed the original beam geometry");
        session.ClearLut();
        return new{lights=12,coverage,bodyUnchanged=true,camera=true,cleared=true,
            boundary="Same captured material and beam geometry; body-only, environment-only and combined actual GPU output. No gameplay or wall-occlusion proof."};
    }
}

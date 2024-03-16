static float PI = 3.141592653589793;

////////////////////////////////////////////////////////////////////////////////////////////////

float Script : STANDARDSGLOBAL <
    string ScriptOutput = "color";
    string ScriptClass  = "scene";
    string ScriptOrder  = "postprocess";
> = 0.8;

texture DepthBuffer : RENDERDEPTHSTENCILTARGET<
    float2 ViewportRatio = {1.0, 1.0};
    string Format        = "D24S8";
>;
texture2D ScnMap : RENDERCOLORTARGET<
    float2 ViewportRatio = {1.0, 1.0};
    int    MipLevels     = 1;
    string Format        = "A8B8G8R8";
>;
sampler2D ScnSamp = sampler_state {
    texture   = <ScnMap>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
};

#ifndef FBM_TEXTURE_NAME
#define FBM_TEXTURE_NAME "fbm1d3ch.png"
#endif

// 非整数ブラウン運動によるノイズ画像
texture2D FBMTexture <
    string ResourceName = FBM_TEXTURE_NAME;
    int    MipLevels    = 1;
>;
sampler2D FBMSamp = sampler_state {
    Texture = <FBMTexture>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = NONE;
    AddressU = WRAP;
    AddressV = WRAP;
};
static float FBMTextureSize = 256.0;
static float FBMTextureBlockSize = 16.0;

float2 ViewportSize : VIEWPORTPIXELSIZE;
static float2 ViewportOffset = float2(0.5,0.5) / ViewportSize;
static float  AspectRatio = ViewportSize.y / ViewportSize.x;

float Time : TIME <bool SyncInEditMode=true;>;

////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef CONTROLLER_NAME
#define CONTROLLER_NAME "EarthquakeProController.pmx"
#endif

float _Level           : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="レベル"; >;
float _RotationPlus    : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="回転+"; >;
float _RotationMinus   : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="回転-"; >;
float _VerticalMinus   : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="縦揺れ-"; >;
float _HorizontalMinus : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="横揺れ-"; >;
float _ScalePlus       : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="スケール+"; >;
float _ScaleMinus      : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="スケール-"; >;
float _FrequencyPlus   : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="周波数+"; >;
float _FrequencyMinus  : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="周波数-"; >;

float3 _BPM    : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="BPM"; >;
float3 _Timing : CONTROLOBJECT < string name=CONTROLLER_NAME; string item="タイミング調整"; >;

static float  Scale       = lerp(lerp(15.0, 50.0, _ScalePlus), 0.0, _ScaleMinus);
static float  MaxOffset   = max(Scale, 0.0) * 0.01;
static float2 MaxOffsetXY = MaxOffset * saturate(float2(1.0 - _HorizontalMinus, 1.0 - _VerticalMinus));
static float  MaxAngle    = lerp(lerp(lerp(0.05, 1.0, _RotationPlus), 0.0, _RotationMinus), 0.0, _ScaleMinus) * PI / 8.0;
static float  Frequency   = lerp(lerp(7.0, 15.0, _FrequencyPlus), 0.05, _FrequencyMinus);
static float  Velocity    = Frequency * FBMTextureBlockSize * 2.0;

////////////////////////////////////////////////////////////////////////////////////////////////

// p must be ≧ 0
float3 FBM(float p) {
    p = fmod(p, FBMTextureSize * FBMTextureSize);
    float x = fmod(p, FBMTextureSize);
    float y = floor(p / FBMTextureSize);
    float2 uv = float2(x, y) / FBMTextureSize;
    float3 h = tex2Dlod(FBMSamp, float4(uv, 0, 0)).rgb; // 0 ≦ h ≦ 1
    return (h - 0.5) * 2.0;
}

float Trauma() {
    float level = max(_Level, 0.0);
    [branch]
    if (abs(_BPM.x) < 1e-5) {
        // 固定値
        return level;
    } else {
        // 自動振動モード
        float interval = 60.0 / _BPM.x;
        float time = Time - _Timing.x / 30.0;
        float t = fmod(time, interval);
        if (t < 0.0) t += interval;
        return lerp(1.0, level, t / interval);
    }
}

// https://www.youtube.com/watch?v=tu-Qe66AvtY&t=209s
float3 EarthquakeOffsetAndAngle() {
    float  trauma = Trauma();
    float3 r = FBM(Time * Velocity); // -1 ≦ r ≦ 1
    float2 offset = r.xy * (trauma * trauma) * float2(AspectRatio, 1.0) * MaxOffsetXY;
    float  angle  = r.z  * (trauma * trauma) * MaxAngle;
    return float3(offset, angle);
}

float2 Rotate(float2 pos, float angle) {
    float2x2 rot = float2x2(
         cos(angle), sin(angle),
        -sin(angle), cos(angle)
    );
    pos = pos * float2(1.0, AspectRatio);
    pos = mul(pos, rot);
    pos = pos / float2(1.0, AspectRatio);
    return pos;
}

static float3 OffsetAndAngle = EarthquakeOffsetAndAngle();

void VS_Earthquake(
    in float4 pos : POSITION,
    in float4 coord : TEXCOORD0,
    out float4 oPos : POSITION,
    out float2 oCoord : TEXCOORD0
) {
    float2 offset = OffsetAndAngle.xy;
    float  angle  = OffsetAndAngle.z;
    oPos = float4(Rotate(pos.xy, angle) + offset, pos.zw);
    oCoord = coord.xy + ViewportOffset;
}

float4 PS_Earthquake(in float2 coord : TEXCOORD0) : COLOR {   
	return tex2D(ScnSamp, coord);
}

////////////////////////////////////////////////////////////////////////////////////////////////

// レンダリングターゲットのクリア値
float4 ClearColor = {1, 1, 1, 0};
float ClearDepth  = 1.0;

technique Earthquake <
    string Script = 
        "RenderColorTarget0=ScnMap;"
        "RenderDepthStencilTarget=DepthBuffer;"
        "ClearSetColor=ClearColor;"
        "ClearSetDepth=ClearDepth;"
        "Clear=Color;"
        "Clear=Depth;"
        "ScriptExternal=Color;"
        "RenderColorTarget0=;"
        "RenderDepthStencilTarget=;"
        "Pass=Earthquake;"
    ;
> {
    pass Earthquake < string Script= "Draw=Buffer;"; > {
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_Earthquake();
        PixelShader  = compile ps_3_0 PS_Earthquake();
    }
}

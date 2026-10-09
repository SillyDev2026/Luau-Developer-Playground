// Official engine API metadata is generated in CI from the Roblox Studio dump.
// Fallback provides useful completions when offline or hosted from a raw branch.
const functions = methods => methods.map(([n,s,r])=>[n,'function',s,r]);
export const CORE_API = {
  types:['Instance','DataModel','Workspace','Players','Player','Humanoid','BasePart','Part','Model','ReplicatedStorage','ServerStorage','ServerScriptService','RunService','TweenService','UserInputService','CollectionService','RemoteEvent','RemoteFunction','BindableEvent','ModuleScript','Script','LocalScript','Vector3','Vector2','CFrame','Color3','UDim','UDim2'],
  classes:{
    Instance:[['Name','property','Name: string','string'],['Parent','property','Parent: Instance?','Instance'],...functions([['FindFirstChild','FindFirstChild(name: string, recursive: boolean?): Instance?','Instance'],['WaitForChild','WaitForChild(name: string, timeout: number?): Instance','Instance'],['GetChildren','GetChildren(): {Instance}','table'],['GetDescendants','GetDescendants(): {Instance}','table'],['IsA','IsA(className: string): boolean','boolean'],['Destroy','Destroy(): ()','nil'],['GetAttribute','GetAttribute(name: string): any','any'],['SetAttribute','SetAttribute(name: string, value: any): ()','nil']])],
    DataModel:functions([['GetService','GetService(serviceName: string): Instance','Instance']]),
    Workspace:[['Gravity','property','Gravity: number','number'],['CurrentCamera','property','CurrentCamera: Camera','Camera'],...functions([['Raycast','Raycast(origin: Vector3, direction: Vector3, params: RaycastParams?): RaycastResult?','RaycastResult']])],
    Players:[['LocalPlayer','property','LocalPlayer: Player','Player'],...functions([['GetPlayers','GetPlayers(): {Player}','table'],['GetPlayerFromCharacter','GetPlayerFromCharacter(character: Model): Player?','Player']])],
    Player:[['Character','property','Character: Model?','Model'],['UserId','property','UserId: number','number'],['DisplayName','property','DisplayName: string','string'],['CharacterAdded','event','CharacterAdded(character: Model)','RBXScriptSignal']],
    Humanoid:[['Health','property','Health: number','number'],['MaxHealth','property','MaxHealth: number','number'],...functions([['TakeDamage','TakeDamage(amount: number): ()','nil'],['MoveTo','MoveTo(location: Vector3): ()','nil']])],
    Part:[['Position','property','Position: Vector3','Vector3'],['Size','property','Size: Vector3','Vector3'],['Anchored','property','Anchored: boolean','boolean'],['CFrame','property','CFrame: CFrame','CFrame']],
    Model:[['PrimaryPart','property','PrimaryPart: BasePart?','BasePart'],...functions([['PivotTo','PivotTo(target: CFrame): ()','nil'],['GetPivot','GetPivot(): CFrame','CFrame']])],
    RemoteEvent:functions([['FireServer','FireServer(...any): ()','nil'],['FireClient','FireClient(player: Player, ...any): ()','nil'],['FireAllClients','FireAllClients(...any): ()','nil']]),
    RemoteFunction:functions([['InvokeServer','InvokeServer(...any): ...any','any'],['InvokeClient','InvokeClient(player: Player, ...any): ...any','any']]),
    TweenService:functions([['Create','Create(instance: Instance, info: TweenInfo, propertyTable: table): Tween','Tween']]),
    RunService:[['Heartbeat','event','Heartbeat(deltaTime: number)','RBXScriptSignal'],['RenderStepped','event','RenderStepped(deltaTime: number)','RBXScriptSignal']],
    Vector3:[['X','property','X: number','number'],['Y','property','Y: number','number'],['Z','property','Z: number','number'],['Magnitude','property','Magnitude: number','number'],...functions([['Dot','Dot(other: Vector3): number','number'],['Cross','Cross(other: Vector3): Vector3','Vector3'],['Lerp','Lerp(to: Vector3, alpha: number): Vector3','Vector3']])],
    RBXScriptSignal:functions([['Connect','Connect(callback: (...any) -> ()): RBXScriptConnection','RBXScriptConnection'],['Wait','Wait(): ...any','any'],['Once','Once(callback: (...any) -> ()): RBXScriptConnection','RBXScriptConnection']]),
  },
  enums:{Material:['Plastic','Wood','Metal','Neon','Glass','Concrete','Grass'],KeyCode:['A','B','C','Space','Return','LeftShift'],EasingStyle:['Linear','Sine','Quad','Cubic','Quart','Quint'],EasingDirection:['In','Out','InOut']},
  standard:{math:functions([['abs','abs(x: number): number','number'],['floor','floor(x: number): number','number'],['ceil','ceil(x: number): number','number'],['sqrt','sqrt(x: number): number','number'],['log10','log10(x: number): number','number'],['max','max(...number): number','number'],['min','min(...number): number','number']]),table:functions([['insert','insert(t: table, v: any): ()','nil'],['remove','remove(t: table, pos: number?): any','any'],['sort','sort(t: table, compare: function?): ()','nil'],['create','create(count: number, value: any?): table','table'],['clear','clear(t: table): ()','nil'],['clone','clone(t: table): table','table']]),string:functions([['format','format(fmt: string, ...any): string','string'],['sub','sub(s: string, i: number, j: number?): string','string'],['find','find(s: string, pattern: string): number?','number'],['gsub','gsub(s: string, pattern: string, repl: string): string','string']]),buffer:functions([['create','create(size: number): buffer','buffer'],['readu8','readu8(buf: buffer, offset: number): number','number'],['writeu8','writeu8(buf: buffer, offset: number, value: number): ()','nil']]),task:functions([['wait','wait(seconds: number?): number','number'],['spawn','spawn(fn: function, ...any): thread','thread'],['delay','delay(seconds: number, fn: function): thread','thread']])}
};

let loaded=CORE_API, loader=null;
export function getRobloxAPI(){return loaded;}
export async function loadRobloxAPI(){
  if(loader)return loader;
  loader=(async()=>{
    try{
      for(const path of ['../roblox-api.json','../public/roblox-api.json']){
        const response=await fetch(new URL(path,import.meta.url),{cache:'force-cache'});
        if(!response.ok)continue;
        const data=await response.json();
        if(!data?.classes||Object.keys(data.classes).length<200)continue;
        loaded={...CORE_API,...data,standard:CORE_API.standard};
        return loaded;
      }
      return loaded;
    }catch{return loaded;}
  })();
  return loader;
}

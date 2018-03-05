%
%  XTCreateSurfaces
%
%
%  Installation:
%
%  -For this XTension to work:
%  
%   1)	Create a new Folder for �batchable� XTensions
%       a.	c:/Program Files/Bitplane/BatchXTensions
%       b.	This folder can be made anywhere, but should be in public folder
%   2)	Download XTBatchProcess.m to this folder
%   3)	Download XTCreateSurfaces.m to this folder
%   4)  Create a new folder that will contain the processed Imaris files and exported
%       statistics that are generated by this Xtension
%       a. g:/BitplaneBatchOutput
%       b. A folder titled BitplaneBatchOutput can be made anywhere just
%       change line 80 of this script to reflect its location.
%   5)	Start Imaris and Click menu tab FIJI>>OPTIONS
%       a.	Add the BatchXTensions folder to the XTension folder window
%       b.	This is necessary for the batch process option to appear in Imaris menu
%  
%
%   NOTE: This XTension will NOT appear in the Imaris menus, and will only appear 
%   in conjunction with the running of the XTBatchProcess XTension
%   
%   NOTE:  This XTension is developed for working on Windows based machines only.
%   If you want to use it on MacOS, you will have to edit the .m file save location
%   to fit Mac standards. 
%
%

function XTCreateSurfaces(aImarisApplicationID)

% connect to Imaris interface
if ~isa(aImarisApplicationID, 'Imaris.IApplicationPrxHelper')
  if ~exist('ImarisLib')
      javaaddpath ImarisLib.jar
  end
  vImarisLib = ImarisLib;
  if ischar(aImarisApplicationID)
    aImarisApplicationID = round(str2double(aImarisApplicationID));
  end
  vImarisApplication = vImarisLib.GetApplication(aImarisApplicationID);
else
  vImarisApplication = aImarisApplicationID;
end

if isempty(vImarisApplication)
    error('Could not connect to Imaris!')
end

%% Open the corresponding .mat file with the regions
filepath = char(vImarisApplication.GetCurrentFileName);

% Find out if there is one or multiple regions
regionfilepath = [filepath(1:end-3) 'mat'];
pathstr = fileparts(regionfilepath);

try
    S = load(regionfilepath);
    todo = createSurfaces(vImarisApplication,S.clipb);
catch err
    % We are in the multiple file case
    % find out the filenames
    filesToProcess = dir([filepath(1:end-4) '_roi*.mat']);
    filesToProcessPath = sort(arrayfun(@(x) x.name, filesToProcess, 'UniformOutput',false));
    todo=[];
    levs=regexp(filesToProcessPath,'(?<prefix>.*roi)(?<level>[0-9]+)(?<sublevel>[a-z]+)?(?<suffix>.*)','names');
        
    levels=unique(cellfun(@(x) x.level,levs));
    for levi = 1:length(levels)
        lev = levels(levi);
        pth = fullfile(pathstr,filesToProcessPath{levi});
        
        levm = cellfun(@(x) strcmp(x.level,num2str(lev)),levs);
        levm_n = find(levm);
        
        sublevs = levs(levm);
        
        if sum(levm)>1 && ~isempty(sublevs{1}.sublevel)
            error(['Missing "level 0" roi for ' filepath ' and roi ' lev.level]);
        end
        
        % Process level 0 ROI
        S = load(pth);
        newsurf = createSurfaces(vImarisApplication,S.clipb);
        
        if sum(levm)>1 && length(newsurf)>1
            error('Can''t do multiple sublevels on more than one level-0 surface');
        end
        
        todo = [todo newsurf];
        
        if length(newsurf)>1
            continue
        end
              
        sname = newsurf.GetName();
        
        for slevi = 2:length(sublevs)
            sublev = sublevs{slevi};
            
            pth = fullfile(pathstr,[sublev.prefix sublev.level sublev.sublevel sublev.suffix]);
            S = load(pth);
            S.clipb.objectsName = sname;
            
            todo = [todo createSurfaces(vImarisApplication,S.clipb)];
        end   
    end
end
%%
% The following MATLAB code returns the name of the dataset opened in 
% Imaris and saves file as IMS (Imaris5) format
vFileNameString = vImarisApplication.GetCurrentFileName; % returns �C:/Imaris/Images/retina.ims�
vFileName = char(vFileNameString);
[vOldFolder, vName, vExt] = fileparts(vFileName); % returns [�C:/Imaris/Images/�, �retina�, �.ims�]
vNewFileName = fullfile('f:/BitplaneBatchOutput', [vName, vExt]); % returns �c:/BitplaneBatchOutput/retina.ims�
vImarisApplication.FileSave(vNewFileName, '');
end

function todo = createSurfaces(vImarisApplication,clipb)
%% Figure out N
N = 0;
typs = fieldnames(clipb.regions)';

for typ = typs;
 mtyp = typ{1};

 cregs = clipb.regions.(mtyp);
 
 if ~isfield(cregs,'position')
     continue
 end
 
 N = N+numel(cregs);
end

%% Fetch measurements
%%% !! Need to modify sortomatograph to export the original objects name
%%% too (e.g. TCR Tg...) so that it can be opened here
objectsName = clipb.objectsName;

surpassObjects = xtgetsporfaces(vImarisApplication);
names = {surpassObjects.Name};
listValue = find(cellfun(@(x) strcmp(x,objectsName),names),1);
xObject = surpassObjects(listValue).ImarisObject;

statStruct = xtgetstats(vImarisApplication, xObject, 'ID', 'ReturnUnits', 1);

xData = statStruct(clipb.xvar).Values;
yData = statStruct(clipb.yvar).Values;

%% Extract surfaces for each region
xScene = vImarisApplication.GetSurpassScene;
xFactory = vImarisApplication.GetFactory;
xObject = xFactory.ToSurfaces(xObject);

todo=[];

for typ = typs;
 mtyp = typ{1};

 cregs = clipb.regions.(mtyp);
 
 if ~isfield(cregs,'position')
     continue
 end
 
 for ir = 1:length(cregs)
    regionName = cregs(ir).label;
     
    rgnVertices = toVertices(cregs(ir),mtyp);
    
    inPlotIdxs = inpolygon(xData, yData, ...
        rgnVertices(:, 1), rgnVertices(:, 2));

    % Same as create new surface with 'inside' objects
    inIDs = double(statStruct(clipb.yvar).Ids(inPlotIdxs));
    inIdxs = inIDs-double(min(statStruct(clipb.yvar).Ids));
    
    sortSurfaces = xFactory.CreateSurfaces;
    
    sortSurfaces.SetName([char(xObject.GetName) ' - ' regionName(6:end)])
    
    if strfind(char(vImarisApplication.GetVersion()),' 9.')
        sortSurfaces = xObject.CopySurfaces(inIdxs);
        sortSurfaces.SetName([char(xObject.GetName) ' - ' regionName(6:end)]);
        xScene.AddChild(sortSurfaces,-1);
    else
        for s = 1:length(inIdxs)
            % Get the surface data for the current index.
            sNormals = xObject.GetNormals(inIdxs(s));
            sTime = xObject.GetTimeIndex(inIdxs(s));
            sTriangles = xObject.GetTriangles(inIdxs(s));
            sVertices = xObject.GetVertices(inIdxs(s));
            
            % Add the surface to the sorted Surface using the data.
            sortSurfaces.AddSurface(sVertices, sTriangles, sNormals, sTime)
            
        end % for s
        
        % Place the sorted Surfaces into the Imaris scene.
        xScene.AddChild(sortSurfaces, -1)
    end

    todo=[todo sortSurfaces]
 end
end
end

function rgnVertices = toVertices(shape,typ) 
    switch typ
        case 'Ellipse'
            % Get the position of the ellipse to use for the graph.
            rgnPosition = shape.position;

            % The position vector is a bounding box. Convert the dims to radii
            % and the center.
            r1 = rgnPosition(3)/2;
            r2 = rgnPosition(4)/2;
            eCenter = [rgnPosition(1) + r1, rgnPosition(2) + r2];

            % Generate an ellipse in polar coordinates using the radii.
            theta = transpose(linspace(0, 2*pi, 100));
            r = r1*r2./(sqrt((r2*cos(theta)).^2 + (r1*sin(theta)).^2));

            [ellX, ellY] = pol2cart(theta, r);
            rgnVertices = [ellX + eCenter(1), ellY + eCenter(2)];

        case 'Poly'
            % The getPosition method returns vertices for polygons.
            rgnVertices = shape.position;

        case 'Rect'
            rgnPosition = shape.position;
            
            % Convert the x-y-width-height into the 4 corners of the rectangle.
            % The order is important to generate a rectangle, rather than a 'z'.
            rgnVertices = zeros(4, 2);
            rgnVertices(1, :) = rgnPosition(1:2); % Lower-left
            rgnVertices(2, :) = [rgnPosition(1) + rgnPosition(3), rgnPosition(2)];
            rgnVertices(3, :) = [rgnPosition(1) + rgnPosition(3), ...
                rgnPosition(2) + rgnPosition(4)];
            rgnVertices(4, :) = [rgnPosition(1), rgnPosition(2) + rgnPosition(4)];

        otherwise % It's a freehand region.
            warning('Skipping Freehand region');
    end % switch
end



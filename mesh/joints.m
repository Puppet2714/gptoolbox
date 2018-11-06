function [VV,FF,WrV,WrF,JJ] = joints(V,E,varargin)
  % JOINTS Construct joints around a wire mesh given as a graph
  % 
  % [VV,FF,RV,RF,PRV,PE] = joints(V,E);
  % [VV,FF,RV,RF,PRV,PE] = joints(V,E,'ParameterName',ParameterValue, ...)
  %
  % Inputs:
  %   V  #V by 3 list of wire graph vertex positions
  %   E  #E by 2 list of edge indices into V
  %   Optional:
  %     'EmbossHeight' followed by height of embossed letters
  %       {0.5*JointThickness}
  %     'LabelSockets'  followed by whether to label sockets with an engraved
  %        number
  %     'JointThickness' followed by thickness of joints {0.25*Radius}
  %     'Overhang'  followed by amount of overhang passed end of joint
  %       {2*Radius}
  %     'PolySize'  followed by number of sides on dowel rod cross-sectional
  %       polygon
  %     'Radius'  followed by dowel rod radius
  %     'Tol'  followed by engineering tolerance
  % Outputs:
  %   VV  #VV by 3 list of vertex positions of joint mesh
  %   FF  #FF by 3 list of triangle indices into VV of joint mesh
  %   WrV  #WrV by 3 list of vertex positions of rod mesh
  %   WrF  #WrF by 3 list of triangle indices into VV of rod mesh
  %   JJ  #FF list of indices into rows of V indicating about which vertex this
  %     joint is.
  %   

  % default values
  poly = 5;
  r = 0.05;
  tol = 0.01;
  hang = [];
  th = [];
  emboss_height = [];
  label_sockets = false;
  % Map of parameter names to variable names
  params_to_variables = containers.Map( ...
    {'EmbossHeight' ,'JointThickness','LabelSockets','Overhang','PolySize','Radius','Tol'}, ...
    {'emboss_height','th','label_sockets','hang','poly','r','tol'});
  v = 1;
  while v <= numel(varargin)
    param_name = varargin{v};
    if isKey(params_to_variables,param_name)
      assert(v+1<=numel(varargin));
      v = v+1;
      % Trick: use feval on anonymous function to use assignin to this workspace
      feval(@()assignin('caller',params_to_variables(param_name),varargin{v}));
    else
      error('Unsupported parameter: %s',varargin{v});
    end
    v=v+1;
  end

  if isempty(th)
    th = 0.25*r;
  end
  if isempty(emboss_height)
    emboss_height = 0.5*th;
  end
  if isempty(hang)
    hang = 2*r;
  end

  % R: outer thickness of cylindrical part of bar
  R = (r+tol);

  U = normalizerow(V(E(:,2),:)-V(E(:,1),:));
  A = adjacency_matrix(E);
  n = size(V,1);
  ne = size(E,1);
  theta = inf(ne,2);
  E2V = sparse(repmat(1:ne,2,1)',E,[ones(ne,1),-ones(ne,1)],ne,n);

  % loop over edges
  for ei = 1:ne
    % loop over each direction
    for c = 1:2
      i = E(ei,c);
      j = E(ei,3-c);
      % other edges
      N = setdiff(find(E2V(:,i)),ei);
      for nei = reshape(N,1,[])
        flip = (E(nei,c) == i)*2-1;
        theta(ei,c) = min(theta(ei,c),acos(flip*sum(U(ei,:).*U(nei,:),2)));
      end
    end
  end
  J = R./atan(theta./2);

  offset = @(V,E,J) [ ...
    V(E(:,1),:)+U.*J(:,1); ...
    V(E(:,2),:)-U.*J(:,2)];
  ZV = offset(V,E,min(J-th*sqrt(2),2*R));
  HV = offset(V,E,J+hang);
  JV = offset(V,E,J);
  WV = offset(V,E,J+th);
  PE = [1:ne;ne+(1:ne)]';

  [JRV,JRF,JRJ,JRI] = edge_cylinders(JV,PE,'Thickness',2*R,'PolySize',poly);
  [WrV,WrF,WrJ,WrI] = edge_cylinders(WV,PE,'Thickness',2*r,'PolySize',poly);
  [HOV,HOF,HOH,HOI] = edge_cylinders(HV,PE,'Thickness',2*(1+2*(1-cos(pi/poly)))*(r+th+tol),'PolySize',poly);
  [ZOV,ZOF,ZOZ,ZOI] = edge_cylinders(ZV,PE,'Thickness',2*(1+2*(1-cos(pi/poly)))*(r+th+tol),'PolySize',poly);

  %clf;
  %hold on;
  %tsurf(JRF,JRV,'FaceColor',[1 0 0],falpha(0.5,0));
  %tsurf(WrF,WrV,'FaceColor',[0 1 0],falpha(0.5,0));
  %tsurf(HOF,HOV,'FaceColor',[0 0 1],falpha(0.5,0));
  %tsurf(ZOF,ZOV,'FaceColor',[1 1 0],falpha(0.5,0));
  %hold off;
  %axis equal;view(2);
  %error

  VV = [];
  FF = [];
  JJ = [];
  % Loop over vertices
  for i = 1:n
    Vi = [V(i,:);  ...
      HOV(E(HOI)==i,:) ;  ...
      ZOV(E(ZOI)==i,:)];
    Fi = convhull(Vi);
    FF = [FF;size(VV,1)+Fi];
    VV = [VV;Vi];
    JJ = [JJ;repmat(i,size(Fi,1),1)];
  end

  fprintf('labeling sockets...\n');
  % Build labels at the end of each piece of wood
  LV = [];
  LF = [];
  if label_sockets
    % loop over edges
    for ei = 1:ne
      % loop over each direction
      [LVei,LFei] = text_to_mesh(sprintf('%02d',ei),'TriangleFlags',' ');
      LVei = LVei-0.5*(max(LVei)-min(LVei));
      LVei = LVei/max(normrow(LVei));
      LVei(:,3) = LVei(:,3)/max(LVei(:,3));
      LVei = LVei*diag([r-th r-th emboss_height]);
      for c = 1:2
        i = E(ei,c);
        j = E(ei,3-c);
        Evec = normalizerow(V(j,:)-V(i,:));
        [w,a] = axisanglebetween(Evec,repmat([0 0 1],size(Evec,1),1));
        R = axisangle2matrix(w,a);
        LVi = (LVei+[0 0 J(ei,c)])*R+V(i,:);
        LF = [LF;LFei+size(LV,1)];
        LV = [LV;LVi];
      end
    end
  end

  fprintf('boolean...\n')
  m = size(FF,1);
  [VV,FF,mJJ] = mesh_boolean(VV,FF,[JRV;LV],[JRF;size(JRV,1)+LF],'minus');
  [~,C] = connected_components(FF);
  CJ = zeros(max(C),1);
  CJ(C(mJJ<=m)) = JJ(mJJ(mJJ<=m));
  JJ = CJ(C);


  % sanity check
  fprintf('check...\n')
  assert(isempty(intersect_other(VV,FF(doublearea(VV,FF)>0,:),WrV,WrF)));
end

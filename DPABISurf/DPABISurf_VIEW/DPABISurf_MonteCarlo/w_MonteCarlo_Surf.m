function ClustSizeInfo=w_MonteCarlo_Surf(SurfFiles, FWHM, VoxelP, AlphaLevels, M, OutTxtFile, MskFiles, AreaFiles)
% Surface-based Monte Carlo Simulation
% Usage: ClustSizeInfo=w_MonteCarlo_Surf(SurfFiles, FWHM, VoxelP, AlphaLevels, M, OutTxtFile, MskFiles, AreaFiles)
%
% Input:
%     SurfFiles     - Surface file list, nx1 cell.
%     FWHM          - Full width half high kernel for smoothing
%     VoxelP        - Voxel-level P thresholds, nx1 vector
%     AlphaLevels   - Cluster-level P thresholds, nx1 vector
%     M             - Number of Iterations
%     OutTxtFile    - Monte Carlo Table
%     MskFiles      - Vertex file list, empty or nx1 cell.
%     AreaFiles     - Area file list, empty or nx1 cell
%
% Output:
%     ClustSizeInfo - ClustSim Info Structure
%
% Written by Sandy Wang 20200725.
% Montreal Neurological Institute (MNI), McGill University.
% sandywang.rest@gmail.com

% Revised by YAN Chao-Gan, 20200811.

if exist('MskFiles', 'var') && ~isempty(MskFiles)
    if numel(SurfFiles)~=numel(MskFiles)
        error('Applied Mask files, but unmatched number of Surface and Mask files');
    end
end

if exist('AreaFiles', 'var') && ~isempty(AreaFiles)
    if numel(SurfFiles)~=numel(MskFiles)
        error('Applied Area files, but unmatched number of Surface and Area files');
    end
end

NumEstimate=numel(SurfFiles);

NumSmoothIters=w_FWHMToNITERS_Surf(FWHM, SurfFiles);

% VoxelP
NumVoxelP=numel(VoxelP);

% Alpha Level
%AlphaLevels=[0.05, 0.025, 0.02, 0.01];
NumAlphaLevel=numel(AlphaLevels);

ClustSizeInfo=cell(NumEstimate, 1);

for n=1:NumEstimate
    % One Tailed & Two Tailed
    S.ClustSizeThrd1=zeros(NumVoxelP, NumAlphaLevel);
    S.ClustSizeThrd2=zeros(NumVoxelP, NumAlphaLevel);
    
    n_smooth_iter=NumSmoothIters(n, 1);
    fprintf('Estimate the number of smooth iteration for FWHM->%f on %s: Smooth Iteration->%d',...
        FWHM, SurfFiles{n}, n_smooth_iter);
    
    % Load Surface files and Residual files
    SurfStruct=gifti(SurfFiles{n});
    
    % Calculate Total Area
    %TotalArea=spm_mesh_area(SurfStruct);
    Vertices=SurfStruct.vertices;
    %Faces=SurfStruct.faces;
    
    NumVertex=size(Vertices, 1);

    % Load area files
    if exist('AreaFiles', 'var') && ~isempty(AreaFiles{n})
        AreaFile=AreaFiles{n};
    else
        DPABISurfPath=fileparts(which('DPABISurf.m'));
        
        [Path, fileN, extn] = fileparts(SurfFiles{n});
        switch fileN
            case 'fsaverage_lh_white.surf'
                AreaFileName='fsaverage_lh_white_avg.area.gii';
            case 'fsaverage_rh_white.surf'
                AreaFileName='fsaverage_rh_white_avg.area.gii';
            case 'fsaverage5_lh_white.surf'                
                AreaFileName='fsaverage5_lh_white_avg.area.gii';
            case 'fsaverage5_rh_white.surf'
                AreaFileName='fsaverage5_rh_white_avg.area.gii';
            otherwise
                error('Invalid Surface File: %s, please select fsaverage or fsaverage5 from SurfTemplates folder',...
                    SurfFiles{n})
        end
        AreaFile=fullfile(DPABISurfPath, 'SurfTemplates', AreaFileName);
    end
    AreaStruct=gifti(AreaFile);
    Area=AreaStruct.cdata;
    S.Area=Area;
    S.AreaFile=AreaFile;
    AreaFiles{n}=AreaFile;
    
    % Load Mask files if exist
    Msk=true(NumVertex, 1);
    if exist('MskFiles', 'var') && ~isempty(MskFiles{n})
        MskStruct=gifti(MskFiles{n});
        if size(MskStruct.cdata, 1)~=size(SurfStruct.vertices, 1)
            error('Unmatched number of vertices for %s and %s',...
                SurfFiles{n}, MskFiles{n});
        end
        Msk=logical(MskStruct.cdata);
    end
    
    ClustSizeNullModel1=zeros(M, NumVoxelP);
    ClustSizeNullModel2=zeros(M, NumVoxelP);
    
    fprintf('Running ClustSim for %s\n', SurfFiles{n});
    for i=1:M
        Fim=randn(NumVertex, 1);
        if n_smooth_iter>0
            Fim=spm_mesh_smooth(SurfStruct, Fim, n_smooth_iter);
        end
        
        FimMean=mean(Fim, 1);
        FimStd=std(Fim, 1);
        %FimSumsq=sum(Fim.^2);
        %FimSuma=sum(Fim);
        %FimStd=sqrt( (FimSumsq-(FimSuma.^2)./NumVertex)./(NumVertex-1) );
    
        for j=1:NumVoxelP
            voxel_p=VoxelP(j);
            fprintf('\titer=%d, voxel_p=%f\n', i, voxel_p);        
            
            % One Tailed & Two Tailed    
            ZThrd1=norminv(1-voxel_p);
            ZThrd2=norminv(1-voxel_p./2);

            XThrd1=FimStd*ZThrd1+FimMean;
            XThrd2=FimStd*ZThrd2+FimMean;
        
            FimThresholded1=Fim.*(Fim>XThrd1);
            FimThresholded2=Fim.*( (Fim>XThrd2) & (Fim<-XThrd2) );
        
            % Apply Mask
            FimMsk1=(FimThresholded1.*Msk)~=0;
            FimMsk2=(FimThresholded2.*Msk)~=0;
        
            CompInd1=spm_mesh_clusters(SurfStruct, FimMsk1);
            CompInd2=spm_mesh_clusters(SurfStruct, FimMsk2);
        
            MaxClustArea1=sum(Area(CompInd1==1));
            MaxClustArea2=sum(Area(CompInd2==1));        
        
            ClustSizeNullModel1(i, j)=MaxClustArea1;
            ClustSizeNullModel2(i, j)=MaxClustArea2;
        end
    end
    
    for j=1:NumVoxelP
        % Obtain Cumulative Distribution
        [pd1, x1]=hist(ClustSizeNullModel1(:, j), M);
        cdf1=cumsum(pd1)./M;
        [pd2, x2]=hist(ClustSizeNullModel2(:, j), M);
        cdf2=cumsum(pd2)./M;
        % Obtain the Threshold of Cluster Size
        for a=1:NumAlphaLevel
            x1_ind=find(cdf1>1-AlphaLevels(a), 1, 'first');
            S.ClustSizeThrd1(j, a)=x1(x1_ind);
        
            x2_ind=find(cdf2>1-AlphaLevels(a), 1, 'first');
            S.ClustSizeThrd2(j, a)=x2(x2_ind);
        end
    end
    
    ClustSizeInfo{n}=S;
end

if exist('OutTxtFile', 'var')==1 && ~isempty(OutTxtFile)
    % Output ClustSim Txt
    fprintf('Output Info to %s\n', OutTxtFile);
    fid=fopen(OutTxtFile, 'w');
    for n=1:NumEstimate
        S=ClustSizeInfo{n};
        fprintf(fid, '----------------------------------------\n');        
        fprintf(fid, 'Surface File: %s\n', SurfFiles{n});
        
        if exist('AreaFiles', 'var')
            fprintf(fid, 'Area File: %s\n', AreaFiles{n});
        else
            fprintf(fid, 'Area File: %s\n', '');
        end
        
        if exist('MskFiles', 'var')
            fprintf(fid, 'Mask File: %s\n', MskFiles{n});
        else
            fprintf(fid, 'Mask File: %s\n', '');
        end
        
        fprintf(fid, 'FWHM=%f, NumOfSmoothIteration=%d\n',...
            FWHM, NumSmoothIters(n));
        fprintf(fid, 'NumOfSimulation=%d\n', M);
        fprintf(fid, '\n');
        % One Tailed
        fprintf(fid, 'One-Tailed Table\n');
        fprintf(fid, '  pthr  | alpha = Prob(Cluster (mm^2) >= given size)\n');
        Str=' ------ |';
        for a=1:NumAlphaLevel
            Str=[Str, sprintf(' %.5f', AlphaLevels(a))];
        end
        fprintf(fid, '%s\n', Str);
        for j=1:NumVoxelP
            Str=sprintf('%.6f ', VoxelP(j));
            for a=1:NumAlphaLevel
                Str=[Str, sprintf('%8.2f', S.ClustSizeThrd1(j, a))];
            end
            fprintf(fid, '%s\n', Str);
        end
        fprintf(fid, '\n');
        % Two Tailed
        fprintf(fid, 'Two-Tailed Table\n');
                fprintf(fid, '  pthr  | alpha = Prob(Cluster (mm^2) >= given size)\n');
        Str=' ------ |';
        for a=1:NumAlphaLevel
            Str=[Str, sprintf(' %.5f', AlphaLevels(a))];
        end
        fprintf(fid, '%s\n', Str);
        for j=1:NumVoxelP
            Str=sprintf('%.6f ', VoxelP(j));
            for a=1:NumAlphaLevel
                Str=[Str, sprintf('%8.2f', S.ClustSizeThrd2(j, a))];
            end
            fprintf(fid, '%s\n', Str);
        end
        fprintf(fid, '\n');
    end
    fclose(fid);
end

% *************************************************************************
% * This file is part of Matlab Toolbox.
% * Copyright 2018 University of Bonn
% *
% * authors:
% *  - Sebastian Merzbach <smerzbach@gmail.com>
% *
% * file creation date: 2018-06-11
% *
% *************************************************************************
%
% Semi-automatic patch extraction via NXCC-based template matching.
%
% Initially, a template has to be selected. Further samples similar to the
% selected patch are suggested by looking for local maxima from the normalized
% cross correlation (NXCC) map between the input and the template. Sample center
% positions can be manually moved (left click) and selected / unselected (right
% click) before extraction. Samples are assigned to two classes (positive /
% negative) based on the peak value in the NXCC map. The threshold for the
% assignment can be chosen interactively. Samples too close to the image borders
% are excluded since they could not be cropped at the desired resolution.
% When exporting, samples can be assigned a specific predefined class type.
%
% Dependencies:
% git clone https://github.com/smerzbach/matlabtools.git
% into the dependencies folder

% put dependencies into search path
mpath = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(mpath, 'dependencies')));

input_dir = 'sample_images';
output_dir = 'patches';

% defaults
template_size = 32;
resizable_template = true;
inspect_template = false; % start external viewer that allows for closer inspection of the selected template

% iterate over all images in input folder
fnames = dir_no_dots(fullfile(input_dir, '*.jpg'));
ks = cell(numel(fnames), 1); % stores the sample generator objects to be on the save side
for fi = 1 : numel(fnames)
    ks{fi} = sample_generator(fnames{fi},...
        'template_size', template_size,...
        'inspect_template', inspect_template, ...
        'resizable_template', resizable_template,...
        'output_dir', output_dir);
    % wait for main figure to be closed
    uiwait(ks{fi}.fh);
end

% we also export the generator objects in case some of their parameters are
% required at a later point
save(fullfile(output_dir, sprintf('sample_generators_%s.mat', ...
    datestr(now, 'yy_mm_dd-HH_MM_SS'))), 'ks');

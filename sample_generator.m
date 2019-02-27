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
classdef sample_generator < handle
    properties(Constant)
        supported_pattern_types = {'type1', 'type2'};
    end
    
    properties
        template_size = 40; % square template size
        resizable_template = false; % allow resizing the template?
        inspect_template = true; % start external viewer that allows for closer inspection of the selected template
        
        output_dir = './patches/'; % default target directory
        im_path; % path to the image, used for writing output images
        im_orig; % input image
        im_gray; % grayscale version for cross correlation computation
        h; % height & width of image
        w;
        
        ROI; % selected region of interest, i.e. the template
        tmpl;
        th; % template height & width
        tw;
        candidates; % patch center candidate map based on local maxima of cross correlation map
        score; % cross correlation score for each potential patch
        xs; % extracted x and y coordinates of the candidate map
        ys;
        offsets; % manual selected pixel offsets for the candidate coordinates
        bad; % indices for excluded patches (those too close to the borders)
        manual_good = []; % indices of manually included candidates
        manual_bad = []; % indices of manually excluded candidates
        
        % some GUI parameters
        cmap; % color map applied to show the patch score (i.e. the cross correlation score)
        dist_thresh = 10; % pixel threshold for selection
        
        % sample annotation options
        max_font_size = 20;
        min_font_size = 10;
        
        % GUI stuff
        img_template; % img object holding the template, used for live updates
        fh;
        ah;
        roi_rect;
        iv_template;
        sh_score;
        sh_good;
        sh_bad;
        sh_selected;
        slider_thresh;
        ind_sel = [];
        pos0 = [];
        mouse_buttons_pressed = {}; % set of the pressed mouse buttons
    end
    
    methods
        function obj = sample_generator(im_path, varargin)
            % construct with input image and optionally with the desired
            % template size
            [varargin, obj.template_size] = arg(varargin, 'template_size', obj.template_size, false);
            [varargin, obj.resizable_template] = arg(varargin, 'resizable_template', obj.resizable_template, false);
            [varargin, obj.inspect_template] = arg(varargin, 'inspect_template', obj.inspect_template, false);
            [varargin, obj.output_dir] = arg(varargin, 'output_dir', obj.output_dir, false);
            arg(varargin);
            
            obj.cmap = gray(100);
            
            if ~exist('im_path', 'var') || isempty(im_path)
                mpath = fileparts(mfilename('fullpath'));
                im_path = fullfile(mpath, 'sample_images', '0001.jpg');
            end
            
            obj.im_path = im_path;
            obj.im_orig = single(imread(im_path)) / 255;
            obj.im_gray = mean(obj.im_orig, 3);
            [obj.h, obj.w, ~] = size(obj.im_gray);
            
            obj.select_template();
        end
        
        function select_template(obj)
            % initialize with random ROI
            ts2 = obj.template_size / 2;
            r = roi([obj.w / 2 - ts2, 1, obj.w / 2 + ts2; obj.h / 2 - ts2, 1, obj.h / 2 + ts2]);
            
            obj.fh = figure();
            obj.ah = axes('Parent', obj.fh);
            imshow(obj.im_orig, 'Parent', obj.ah);
            obj.ah.Position = [0, 0, 1, 1];
            hold(obj.ah, 'on');
            zah = zoomaxes(obj.ah);
            zah.x_pan = false;
            zah.y_pan = false;
            obj.roi_rect = imrect(obj.ah, obj.roi2pos(r));
            obj.roi_rect.setResizable(obj.resizable_template);
            obj.ROI = obj.pos2roi(round(obj.roi_rect.getPosition()));
            obj.roi_rect.addNewPositionCallback(@(src, evnt) obj.set_template());
            uicontrol(obj.fh, 'Style', 'pushbutton', 'Position', [1, 1, 100, 30], ...
                'String', 'Select', 'FontSize', 16, 'FontWeight', 'bold', ...
                'Callback', @(src, evnt) obj.compute());
            
            % show selected template in separte figure
            obj.ROI.setImage(obj.im_orig);
            obj.img_template = img(obj.ROI.apply(obj.im_orig));
            if obj.inspect_template
                obj.iv_template = iv(obj.img_template);
                obj.iv_template.tonemapper.update_hists = false;
            end
        end
        
        function set_template(obj)
            % update preview of template
            obj.ROI = obj.pos2roi(round(obj.roi_rect.getPosition()));
            obj.ROI.setImage(obj.im_orig);
            obj.img_template.assign(obj.ROI.apply(obj.im_orig)); % automatically updates the viewer
        end
        
        function pos = roi2pos(obj, r) %#ok<INUSL>
            width = r.getXMax() - r.x_min + 1;
            height = r.getYMax() - r.y_min + 1;
            pos = [r.x_min, r.y_min, width, height];
        end
        
        function r = pos2roi(obj, pos)
            r = roi([pos(1), 1, pos(1) + pos(3); pos(2), 1, pos(2) + pos(4)], 'im', obj.im_orig);
            r.setImage(obj.im_gray);
        end
        
        function compute(obj)
            % get template
            obj.ROI.setImage(obj.im_gray);
            obj.tmpl = obj.ROI.apply(obj.im_gray);
            
            % compute half template dimensions
            [obj.th, obj.tw, ~] = size(obj.tmpl);
            obj.th = floor(obj.th / 4) * 2 + 1;
            obj.tw = floor(obj.tw / 4) * 2 + 1;
            % compute center coordinates
            cy = floor(obj.th / 2) + 1;
            cx = floor(obj.tw / 2) + 1;

            % compute normalized cross correlation
            C = normxcorr2(obj.tmpl, obj.im_gray);
            C = C(obj.th : end - obj.th, obj.tw : end - obj.tw); % crop xcorr map to remove padding

            % find maxima in local neighborhood with half the template dimensions
            center = cy + obj.th * (cx - 1);
            not_center = 1 : obj.th * obj.tw;
            not_center(center) = [];
            obj.candidates = nlfilter(C, [obj.th, obj.tw], @(x) all(x(center) >= x(not_center)));

            [obj.ys, obj.xs] = find(obj.candidates);
            obj.offsets = zeros(numel(obj.ys), 2);
            obj.score = C(obj.candidates);
            prom_sorted = sort(obj.score);
            % remove most dominant peaks from template itself
            obj.score(obj.score == prom_sorted(end)) = prom_sorted(end - 1);
            % normalize score between 0.1 and 1
            obj.score = 0.1 + 0.9 * (obj.score - min(obj.score)) / (max(obj.score) - min(obj.score));

            % exclude patch centers that are too close to the image borders
            obj.bad = obj.ys - obj.th < 1 | obj.ys > obj.h - obj.th | obj.xs - obj.tw < 1 | obj.xs > obj.w - obj.tw;
            
            % initialize manual selections
            obj.manual_good = false(numel(obj.xs), 1);
            obj.manual_bad = false(numel(obj.xs), 1);
            
            % start manual selection
            obj.select();
        end
        
        function select(obj)
            % preselect a threshold
            thresh = median(obj.score);
            
            obj.sh_score = scatter(obj.ah, obj.xs, obj.ys, 100 * obj.score, obj.cmap(round(100 * obj.score), :), 'o', 'filled');
            obj.sh_bad = scatter(obj.ah, obj.xs, obj.ys, 150 * obj.score, 'o', 'LineWidth', 1, 'MarkerEdgeColor', 'red');
            obj.sh_good = scatter(obj.ah, obj.xs, obj.ys, 150 * obj.score, 'o', 'LineWidth', 3, 'MarkerEdgeColor', 'green');
            obj.slider_thresh = uicontrol(obj.fh, 'Style', 'slider', 'Min', obj.score2slider(0), 'Max', obj.score2slider(1), ...
                'Value', obj.score2slider(thresh), 'Callback', @(src, evnt) obj.update_selection(obj.slider2score(src.Value)), ...
                'Position', [1, 61, 20, obj.fh.Position(4) - 60]);
            tbox = uicontrol(obj.fh, 'Style', 'text', 'String', sprintf('%3.2f', obj.slider2score(obj.slider_thresh.Value)), 'Position', [1, 31, 50, 30]);
            addlistener(obj.slider_thresh, 'Value', 'PreSet', @(src, evnt) obj.update_selection(obj.slider2score(evnt.AffectedObject.Value)));
            addlistener(obj.slider_thresh, 'Value', 'PreSet', @(src, evnt) set(tbox, 'String', sprintf('%3.2f', obj.slider2score(evnt.AffectedObject.Value))));
            obj.update_selection(thresh);
            
            obj.sh_selected = scatter(obj.ah, obj.xs, obj.ys, 200 * obj.score, 's', 'MarkerEdgeColor', 'blue', 'LineWidth', 2);
            obj.sh_selected.SizeData(:) = nan;
            
            % set mouse callback to individually select / unselect some candidates
            obj.fh.WindowButtonDownFcn = @obj.callback_mouse_down;
            obj.fh.WindowButtonUpFcn = @obj.callback_mouse_up;
            obj.fh.WindowButtonMotionFcn = @obj.callback_mouse_motion;
            
            uicontrol(obj.fh, 'Style', 'pushbutton', 'Position', [101, 1, 100, 30], ...
                'String', 'Extract', 'FontSize', 16, 'FontWeight', 'bold', ...
                'Callback', @(src, evnt) obj.extract());
            uicontrol(obj.fh, 'Style', 'pushbutton', 'Position', [201, 1, 100, 30], ...
                'String', 'Show', 'FontSize', 16, 'FontWeight', 'bold', ...
                'Callback', @(src, evnt) obj.show_patches());
            uicontrol(obj.fh, 'Style', 'pushbutton', 'Position', [301, 1, 100, 30], ...
                'String', 'Save', 'FontSize', 16, 'FontWeight', 'bold', ...
                'Callback', @(src, evnt) obj.write_patches());
        end
        
        function [patches, scores, xs, ys] = extract(obj)
            % extract patches according to scores & manual selections, dumps the
            % variables patches, scores, patch_coords_x and patch_coords_y in
            % the main workspace
            thresh = obj.slider2score(obj.slider_thresh.Value);
            mask_good = obj.score >= thresh & ~(obj.bad | obj.manual_bad) | obj.manual_good;
            ysel = obj.ys(mask_good);
            xsel = obj.xs(mask_good);
            
            scores = obj.score(mask_good);
            [scores, perm] = sort(scores, 'descend');
            xs = afun(@(cx) [cx - obj.tw, cx + obj.tw], xsel(perm));
            ys = afun(@(cy) [cy - obj.th, cy + obj.th], ysel(perm));
            patches = cell(numel(xs), 1);
            for ii = 1 : numel(xs)
                multiWaitbar('extracting patches', (ii - 1) / numel(xs));
                patches{ii} = obj.im_orig(ys{ii}(1) : ys{ii}(2), xs{ii}(1) : xs{ii}(2), :);
            end
            multiWaitbar('extracting patches', 'Close');
            
            if nargout == 0
                % dump into main workspace if not called with return values
                % (i.e. when called from the GUI)
                assignin('base', 'patches', patches);
                assignin('base', 'scores', scores);
                assignin('base', 'patch_coords_x', xs);
                assignin('base', 'patch_coords_y', ys);
            end
        end
        
        function write_patches(obj)
            [patches, scores, patch_coords_x, patch_coords_y] = obj.extract();
            [~, basename, baseext] = fileparts(obj.im_path);
            basepath = fullfile(obj.output_dir, basename);
            if ~exist(obj.output_dir, 'dir')
                mkdir(obj.output_dir);
            end
            [type_index, ok] = listdlg('PromptString', 'Select the pattern type:', 'SelectionMode', 'single', ...
                'ListString', obj.supported_pattern_types);
            if ~ok
                return;
            end
            type = obj.supported_pattern_types{type_index};
            for ii = 1 : numel(patches)
                multiWaitbar('writing patches', (ii - 1) / numel(patches));
                ofname = sprintf('%s_type%s_patch%04d_centerx%04d_centery%04d_score%6.2f%s', ...
                    basepath, type, ii, mean(patch_coords_x{ii}), mean(patch_coords_y{ii}), ...
                    obj.score2slider(scores(ii)), baseext);
                imwrite(uint8(patches{ii} * 255), ofname);
            end
            multiWaitbar('writing patches', 'Close');
            fprintf('wrote %d patches to %s.\n', numel(patches), obj.output_dir);
        end
        
        function show_patches(obj)
            % show a montage of all patches with and without score annotations
            [patches, scores] = obj.extract();
            [height, width] = obj.ROI.getDims;
            font_size = min(obj.max_font_size, max(obj.min_font_size, round(min(height, width) / 10)));
            patches_annot = cell(size(patches));
            for ii = 1 : numel(patches)
                multiWaitbar('annotating patches', (ii - 1) / numel(patches));
                patches_annot{ii} = AddTextToImage(imresize(patches{ii}, 2), ...
                    sprintf('%3.2f', scores(ii) * 100), [2 * size(patches{ii}, 1) - font_size - 1, 1], [1, 1, 1], 'Sans', font_size);
            end
            multiWaitbar('annotating patches', 'Close');
            sv(collage(patches_annot, 'border_width', 3, 'border_value', 0, 'transpose', false), ...
                collage(patches, 'border_width', 3, 'border_value', 0, 'transpose', false));
        end
        
        function update_selection(obj, thresh)
            % apply selected threshold (respecting manual selectins)
            if ~exist('thresh', 'var')
                thresh = obj.slider2score(obj.slider_thresh.Value);
            end
            
            % show good / bad selections by setting the size data to nan
            mask_good = obj.score >= thresh & ~(obj.bad | obj.manual_bad) | obj.manual_good;
            score_good = obj.score;
            score_good(~mask_good) = nan;
            obj.sh_good.SizeData = 150 * score_good;
            
            mask_bad = obj.score < thresh | obj.bad | obj.manual_bad;
            score_bad = obj.score;
            score_bad(~mask_bad) = nan;
            obj.sh_bad.SizeData = 150 * score_bad;
        end
        
        function slider_value = score2slider(obj, score) %#ok<INUSL>
            % map score to slider values
            slider_value = score * 100;
        end
        
        function score = slider2score(obj, slider_value) %#ok<INUSL>
            % map slider values to score
            score = slider_value / 100;
        end
        
        function callback_mouse_down(obj, src, evnt) %#ok<INUSD>
            % mouse button down callback
            if in_axis(obj.fh, obj.ah)
                obj.mouse_buttons_pressed = union(obj.mouse_buttons_pressed, {obj.fh.SelectionType});
                
                pos = round(obj.ah.CurrentPoint(1, 1 : 2));
                dists = sqrt(sum(bsxfun(@minus, [obj.xs, obj.ys] + obj.offsets, pos) .^ 2, 2));
                inds_near = find(dists < obj.dist_thresh);
                if ~isempty(inds_near)
                    [~, ind] = min(dists(inds_near));
                    obj.ind_sel = inds_near(ind);
                end
                
                obj.pos0 = pos;
                obj.callback_mouse_motion();
                
            end
        end
        
        function callback_mouse_up(obj, src, evnt) %#ok<INUSD>
            % mouse button up callback
            if in_axis(obj.fh, obj.ah)
                obj.mouse_buttons_pressed = setdiff(obj.mouse_buttons_pressed, {obj.fh.SelectionType});
                obj.xs = obj.xs + obj.offsets(:, 1);
                obj.ys = obj.ys + obj.offsets(:, 2);
                obj.offsets(:) = 0;
                obj.pos0 = [];
                obj.ind_sel = [];
            end
        end
        
        function callback_mouse_motion(obj, src, evnt) %#ok<INUSD>
            % mouse motion callback
            if in_axis(obj.fh, obj.ah)
                pos = round(obj.ah.CurrentPoint(1, 1 : 2));
                dists = sqrt(sum(bsxfun(@minus, [obj.xs, obj.ys] + obj.offsets, pos) .^ 2, 2));
                inds_near = find(dists < obj.dist_thresh);
                ind_hovered = [];
                if ~isempty(inds_near)
                    [~, ind] = min(dists(inds_near));
                    ind_hovered = inds_near(ind);
                end
                sizes = nan(numel(obj.xs), 1);
                sizes(ind_hovered) = 300 * obj.score(ind_hovered);
                obj.sh_selected.SizeData = sizes;
                if ~isempty(obj.ind_sel)
                    if ismember('alt', obj.mouse_buttons_pressed) && ~obj.bad(obj.ind_sel)
                        if ~isnan(obj.sh_good.SizeData(obj.ind_sel))
                            % unselect
                            obj.manual_good(obj.ind_sel) = false;
                            obj.manual_bad(obj.ind_sel) = true;
                        else
                            % select, but only if its not too near to the border
                            obj.manual_good(obj.ind_sel) = true;
                            obj.manual_bad(obj.ind_sel) = false;
                        end
                    elseif ismember('normal', obj.mouse_buttons_pressed)
                        if ~isempty(obj.pos0)
                            % drag point
                            obj.offsets(obj.ind_sel, :) = pos - obj.pos0;
                            obj.sh_score.XData = obj.xs + obj.offsets(:, 1);
                            obj.sh_score.YData = obj.ys + obj.offsets(:, 2);
                            obj.sh_good.XData = obj.xs + obj.offsets(:, 1);
                            obj.sh_good.YData = obj.ys + obj.offsets(:, 2);
                            obj.sh_bad.XData = obj.xs + obj.offsets(:, 1);
                            obj.sh_bad.YData = obj.ys + obj.offsets(:, 2);
                            obj.sh_selected.XData = obj.xs + obj.offsets(:, 1);
                            obj.sh_selected.YData = obj.ys + obj.offsets(:, 2);
                        end
                    end
                    obj.update_selection();
                end
            end
            obj.sh_selected.LineWidth = 2;
            obj.sh_selected.MarkerEdgeColor = 'yellow';
        end
    end
end

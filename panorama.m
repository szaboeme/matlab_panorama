function panorama()
% an application to create simple panoramic images by manually defining 
% point pairs in photos and computing homographies between them

axislist = zeros(1, 10); % list of axis handles
Naxes = 2; % number of empty axes displayed at start up
maxaxes = 6; % maximum number of allowed axes/images
images = cell(1, maxaxes); % call array of loaded image data
cpoints = cell(maxaxes); % cell array for control point pairs
homs = cell(maxaxes); % cell array of homography matrices
result = []; % the resulting panoramic image - needed for the crop callback

%% create and set up the GUI
screenSize = get(groot, 'ScreenSize');
figSize = [1200, 600];
figPosition = [(screenSize(3:4)-figSize)/2, figSize];

% create a figure
hFig = uifigure('Position', figPosition, ...
    'Name', 'Panorama Stitching', 'Color', 0.8*ones(1,3));

% create the main layout grid
maing = uigridlayout(hFig, [1 2]);
maing.ColumnWidth = {200, '1x'}; % menu part has fixed width

% configure the menu part
leftg = uigridlayout(maing, [11 2]);
leftg.ColumnWidth = {'fit'};
leftg.RowHeight = {30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30};

%% set up menu buttons

% help button with description
bHelp = uibutton(leftg, 'Text', 'Help');
bHelp.Layout.Column = [1 2];
bHelp.Layout.Row = 1;

% add a new image
bAdd = uibutton(leftg, 'Text', 'Add image');
bAdd.Layout.Column = [1 2];
bAdd.Layout.Row = 2;

% make the panoramic image
bMakePanorama = uibutton(leftg, 'Text', 'Make panorama');
bMakePanorama.Layout.Column = [1 2];
bMakePanorama.Layout.Row = 3;

% reset / clear all button
bReset = uibutton(leftg, 'Text', 'Reset');
bReset.Layout.Column = [1 2];
bReset.Layout.Row = 4;

% create image name labels and ordering dropdowns
uilabel(leftg, 'Text', 'Reference');
refdd = uidropdown(leftg, 'Items', cellstr(string(1:Naxes)));
imlabels = zeros(1, maxaxes); % label handles
dds = zeros(1, maxaxes); % dropdown handles

for i = 1:maxaxes
    % set up labels and dropdown menus
    obj1 = uilabel(leftg, 'Text', strcat('#', int2str(i), {' '}, 'in panorama'));
    obj2 = uidropdown(leftg, 'Items', cellstr(string(1:Naxes)));
    if i > Naxes
        % disable the ones after the current number of available image holders
        set(obj1, 'Enable', 'off');
        set(obj2, 'Enable', 'off');
    end
    imlabels(i) = obj1;
    dds(i) = obj2;
end

%% image grid part
rightg = uigridlayout(maing, [2, 3]);
% create axes for image display
% set mouse click callback for axes
for m = 1:Naxes
    obj = createImDisplay(rightg, m);
    axislist(m) = obj; % save the handle to the axis list
    set(axislist(m), 'ButtonDownFcn', @(src, event)openImage(axislist(m)));
end

%% set callbacks
bAdd.ButtonPushedFcn = @(src, event)addImage();
bMakePanorama.ButtonPushedFcn = @(src, event)stitchPanorama();
bHelp.ButtonPushedFcn = @(src, event)showHelp();
bReset.ButtonPushedFcn = @(src, event)reset();

%% display the help window on start up
showHelp();

%% main functions

% image stitching function
    function stitchPanorama()
        % check if all axes have loaded images
        check = checkLoad(Naxes, axislist);
        if check == 0
            errordlg('There are not enough images loaded!', 'Not enough images', 'modal');
            return
        end
        % check for valid image ordering
        check = checkOrder(Naxes, dds);
        if check == 0
            errordlg('Invalid image ordering sequence!', 'Invalid order', 'modal');
            return
        end
        % compute homography between each subsequent image pair
        for im = 1:(Naxes-1)
            getControlPoints(figPosition, 'Control Point Selection', im, im+1);
            % find best homography
            homs{im, im+1} = optH(cpoints{im, im+1}, cpoints{im+1, im});
            if isempty(homs{im, im+1})
                errordlg('The homography matrix could not be computed!', 'Homography error', 'modal');
                return
            end
            homs{im+1, im} = optH(cpoints{im+1, im}, cpoints{im, im+1});
            if isempty(homs{im+1, im})
                errordlg('The homography matrix could not be computed!', 'Homography error', 'modal');
                return
            end
        end
        % compute homographies for every image mapping to the reference
        ref = round(str2double(refdd.Value));
        % set identity for mapping reference image to itself
        homs{ref, ref} = eye(3);
        % compute mapping from index distance 2
        if (ref+2) < (Naxes+1)
            homs{ref, ref+2} = homs{ref+1, ref+2} * homs{ref, ref+1};
            homs{ref+2, ref} = homs{ref+1, ref} * homs{ref+2, ref+1};
        end
        if (ref-2) > 0
            homs{ref, ref-2} = homs{ref-1, ref-2} * homs{ref, ref-1};
            homs{ref-2, ref} = homs{ref-1, ref} * homs{ref-2, ref-1};
        end
        % compute mapping from index distance 3, if needed
        if (ref+3) < (Naxes+1)
            homs{ref, ref+3} = homs{ref+2, ref+3} * homs{ref, ref+2};
            homs{ref+3, ref} = homs{ref+2, ref} * homs{ref+3, ref+2};
        end
        if (ref-3) > 0
            homs{ref-3, ref} = homs{ref-2, ref} * homs{ref-3, ref-2};
            homs{ref, ref-3} = homs{ref-2, ref-3} * homs{ref, ref-2};
        end
        
        % map the whole image
        [ysize, xsize, ~] = size(images{1});
        % image corner coordinates
        corners = [1 1 xsize xsize; ...
            1 ysize 1 ysize; ...
            1 1 1 1];
        maxx = -Inf; maxy = -Inf;
        minx = Inf; miny = Inf;
        % map each image's corners and determine the final image size
        for im = 1:Naxes
            corn = homs{im, ref} * corners;
            corn = corn ./ corn(3,:);
            maxx = max(max(corn(1, :)), maxx);
            minx = min(min(corn(1, :)), minx);
            maxy = max(max(corn(2, :)), maxy);
            miny = min(min(corn(2, :)), miny);
        end
        % result width and height
        W = round(maxx - minx);
        H = round(maxy - miny);
        % x and y shift value of indices when mapping back
        xshift = -round(minx) +1;
        yshift = -round(miny) +1;
        % construct an image
        result = zeros(H, W, 3, 'uint8');
        
        % for each image do
        for im = 1:Naxes
            corn = homs{im, ref} * corners;
            corn = corn ./ corn(3,:);
            maxx = round(max(corn(1, :)));
            minx = round(min(corn(1, :)));
            maxy = round(max(corn(2, :)));
            miny = round(min(corn(2, :)));
            % map each result coordinate 'back' to the image and save the
            % pixel value to the result
            for x = minx:(maxx)
                for y = miny:(maxy)
                    back = homs{ref, im} * [x; y; 1];
                    back = round(back ./ back(3));
                    % only use the pixel color if the remapping is inside
                    % the image
                    if min(back) > 0 && back(2) < ysize && back(1) < xsize
                        result(y+yshift, x+xshift, :) = images{im}(back(2), back(1), :);
                    end
                end
            end
        end
        % autosave in case the user forgets to save later
        imwrite(result, 'result.jpg');
        % create new window for the result
        f = uifigure('Position', figPosition, ...
            'Name', 'Panorama', 'Color', 0.8*ones(1,3));
        g = uigridlayout(f, [2 9]);
        g.RowHeight = {'1x', 35};
        ax = uiaxes(g, 'Visible', 'off');
        ax.Layout.Column = [1 9];
        ax.Layout.Row = 1;
        % show raw result
        imshow(result, 'Parent', ax);
        
        % add buttons
        bsave = uibutton(g, 'Text', 'Save as...');
        bsave.Layout.Row = 2;
        bsave.Layout.Column = 4;
        
        bcrop = uibutton(g, 'Text', 'Crop image');
        bcrop.Layout.Row = 2;
        bcrop.Layout.Column = 5;
        
        bclose = uibutton(g, 'Text', 'Close');
        bclose.Layout.Row = 2;
        bclose.Layout.Column = 6;
        
        % set callbacks
        bcrop.ButtonPushedFcn = @(src, event)crop(ax, bcrop, bsave);
        bsave.ButtonPushedFcn = @(src, event)saveAs(result);
        bclose.ButtonPushedFcn = @(src, event)closeit();
        
        % close callback
        function closeit()
            delete(f);
        end
    end

% create new window and save control points
% called automatically before panorama stitching ?
    function getControlPoints(fpos, name, im1, im2)
        % check if there are any images loaded
        if isempty(images{im1}) || isempty(images{im2})
            errordlg('No images loaded! Check your images.', 'No image', 'modal');
            return
        end
        fig = uifigure('Position', fpos, ...
            'Name', name, 'Color', 0.8*ones(1,3));
        g = uigridlayout(fig, [1 2]);
        g.ColumnWidth = {200, '1x'};
        % button set up
        g2 = uigridlayout(g, [14, 1]);
        g2.RowHeight = {30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30};
        b1 = uibutton(g2, 'Text', 'Add point');
        b2 = uibutton(g2, 'Text', 'Delete last point');
        b3 = uibutton(g2, 'Text', 'Done!');
        % add labels for showing clicked points
        uilabel(g2, 'Text', 'Point pairs:');
        labels = zeros(1, 10);
        for ind = 1:10
            labels(ind) = uilabel(g2, 'Text', ' ');
        end
        % two axes for image display
        g3 = uigridlayout(g, [1 2]);
        ax1 = axes('Parent', g3);
        ax1.Toolbar.Visible = 'off';
        ax2 = axes('Parent', g3);
        ax2.Toolbar.Visible = 'off';
        % load images
        axes(ax1);
        imshow(images{im1}, 'Parent', ax1);
        axes(ax2);
        imshow(images{im2}, 'Parent', ax2);
        % assign callbacks
        b1.ButtonPushedFcn = @(src, event)addpoint();
        b2.ButtonPushedFcn = @(src, event)delpoint();
        b3.ButtonPushedFcn = @(src, evenet)done();
        % if there are some points already loaded
        showpoints();
        
        uiwait(fig);
        plots = []; % plot point handles
        
        % show already registered point pairs
        function showpoints()
            % if no points, return
            if isempty(cpoints{im1, im2})
                return
            end
            s = size(cpoints{im1, im2}, 2);
            cmap = hsv(10);
            % plot point pair on the image pair
            axes(ax1);
            hold(ax1, 'on');
            for k = 1:s
                x = cpoints{im1, im2}(1,k);
                y = cpoints{im1, im2}(2,k);
                x2 = cpoints{im2, im1}(1,k);
                y2 = cpoints{im2, im1}(2,k);
                % show new point in labels
                set(labels(k), 'Text', strcat('[', num2str(x), ', ', ...
                    num2str(y), ']; [', num2str(x2), ', ', num2str(y2), ']'));
                
                plots(k*2 - 1) = plot(ax1, x, y, 'o', 'MarkerSize', 8, ...
                    'MarkerEdgeColor', 'yellow', ...
                    'MarkerFaceColor', cmap(k, :));
            end
            hold(ax1, 'off');
            axes(ax2);
            hold(ax2, 'on');
            for k = 1:s
                x = cpoints{im2, im1}(1,k);
                y = cpoints{im2, im1}(2,k);
                plots(k*2) = plot(ax2, x, y, 'o', 'MarkerSize', 8, ...
                    'MarkerEdgeColor', 'yellow', ...
                    'MarkerFaceColor', cmap(k, :));
            end
            hold(ax2, 'off');
        end
        
        % button callbacks
        function addpoint() % k is the index; at least 4 points, at most 10
            cmap = hsv(10); % pick 10 different colors
            which = size(cpoints{im1, im2}, 2) + 1; % index
            % show image im1 and accept 1 point
            ax = axes;
            imshow(images{im1}, 'Parent', ax);
            title(ax, strcat('Image', {' '}, num2str(im1)));
            [x, y] = ginput(1);
            % save the point
            cpoints{im1, im2}(:, which) = [x; y];
            % show image im2 and accept 1 input point
            axx = axes;
            imshow(images{im2}, 'Parent', axx);
            title(axx, strcat('Image', {' '}, num2str(im2)));
            [x2, y2] = ginput(1);
            delete(gcf);
            % save the point
            cpoints{im2, im1}(:, which) = [x2; y2];
            
            % show new point in labels
            set(labels(which), 'Text', strcat('[', num2str(x), ', ', ...
                num2str(y), ']; [', num2str(x2), ', ', num2str(y2), ']'));
            % plot point pair on the image pair
            axes(ax1);
            hold(ax1, 'on');
            plots(which*2 - 1) = plot(ax1, x, y, 'o', 'MarkerSize', 8, ...
                'MarkerEdgeColor', 'yellow', ...
                'MarkerFaceColor', cmap(which, :));
            hold(ax1, 'off');
            axes(ax2);
            hold(ax2, 'on');
            plots(which*2) = plot(ax2, x2, y2, 'o', 'MarkerSize', 8, ...
                'MarkerEdgeColor', 'yellow', ...
                'MarkerFaceColor', cmap(which, :));
            hold(ax2, 'off');
        end
        
        function delpoint() % delete last clicked point (pair) if there is any
            if ~isempty(cpoints{im1, im2})
                which = size(cpoints{im1, im2}, 2); % get index
                set(labels(which), 'Text', ' '); % delete from labels
                cpoints{im1, im2}(:, end) = []; % delete from the point array
                cpoints{im2, im1}(:, end) = [];
                delete(plots(which*2)); % delete from image plot
                delete(plots(which*2-1));
            end
        end
        
        function done()
            d = dialog('Position', [figSize/2 300 150], 'Name', 'Are you sure?');
            uicontrol('Parent', d, ...
                'Style', 'text', ...
                'Position', [0 80 300 40], ...
                'FontSize', 10, ...
                'String', strcat('Are you done adding points?'));
            
            uicontrol('Parent', d, ...
                'String', 'Cancel', ...
                'Position', [60 30 75 30], ...
                'Callback', 'delete(gcf)');
            
            uicontrol('Parent', d, ...
                'Position', [165 30 75 30], ...
                'String', 'Yes', ...
                'Callback', @(src, event)buttonCallback);
            uiwait(d);
            
            function buttonCallback()
                delete(gcf); % close dialog window
                delete(fig); % close the point selection window
            end
        end
    end

%% homography computation

% compute a homography from point pairs
    function H = getH(u, u0)
        % add row of ones
        u(end+1, :) = ones(1, size(u, 2));
        u0(end+1, :) = ones(1, size(u0, 2));
        
        O = zeros(size(u))';
        uu0 = (-u0(1, :) .* u)';
        uu1 = (-u0(2, :) .* u)';
        % build matrix M from the points
        M = [u' O uu0; O u' uu1];
        % get null space of matrix M
        H = null(M);
        if all(H) % if there are no zeros
            H = reshape(H, [3,3]); % reshape into a 3-by-3 matrix
            H = H./ H(3,3); % divide by lower right element
        else
            H = []; % return empty matrix if there are zeros
        end
    end

% select best homography (best point quadruple from the point pairs)
    function H = optH(u, u0)
        iter = nchoosek(1:size(u, 2), 4);
        
        errbest = Inf;
        bestH = [];
        for k = 1:size(iter,1)
            % pick the points by the index vector
            uu = u(:, iter(k, :));
            uu0 = u0(:, iter(k, :));
            % compute homography from the quadruple
            newH = getH(uu, uu0);
            if isempty(newH)
                continue
            end
            % project all the points with H
            proj = newH * [u; ones(1, size(u, 2))];
            proj = proj ./ proj(3, :);
            % compute projection errors
            e = u0 - proj(1:2, :);
            errs = vecnorm(e, 2, 1);
            errmax = max(errs);
            % minimize the maximum error, select best H
            if errmax < errbest
                errbest = errmax;
                bestH = newH;
            end
        end
        % return the mapping with the least maximum error
        H = bestH';
    end

%% helper functions

% show help window
    function showHelp()
        fig = uifigure('Position', [figSize/2-100 650 600], 'Name', 'Help');
        g = uigridlayout(fig, [11 1]);
        g.RowHeight = {'1x', 30};
        
        welcome = 'Welcome to the Panorama Stitcher!';
        uilabel(g, 'Text', welcome, 'FontSize', 16, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on', ...
            'FontWeight', 'bold');
        
        str1 = 'This application allows you to load a set of images to make a panoramic photo. Follow the steps below to learn how it works.';
        uilabel(g, 'Text', str1, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step1 = '1. Load a set of photos by using the Load new button at each window. To add more images, use the Add image button. You can unload an image by clicking Clear, or delete an image placeholder by clicking Delete.';
        uilabel(g, 'Text', step1, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step2 = '2. Using the dropdown menus on the left, select your reference image and order the loaded images how you wish them to appear in the panorama.';
        uilabel(g, 'Text', step2, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step3 = '3. After loading the photos and setting the order, click the Make panorama button. This will open a new window.';
        uilabel(g, 'Text', step3, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step4 = '4. In the Control Point Selection window, mark at least 4 point pairs on the neighbouring images by using the Add point option. The point pairs will appear on the images. Use the Delete last point option if you are not satisfied with the point.';
        uilabel(g, 'Text', step4, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step5 = '5. Click Done! if you are satisfied with the point pairs. Do this for each image pair.';
        uilabel(g, 'Text', step5, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step6 = '6. After clicking Done! in the last image pair point selection window, the application constructs the panoramic photo. This may take a while.';
        uilabel(g, 'Text', step6, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step7 = '7. The application automatically saves the result. You can use the Save as... option to save, or the Crop to crop the photo before saving.';
        uilabel(g, 'Text', step7, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        step8 = 'Cropping: Use the arrow keys to move the red lines: e.g. left arrow to move the right border left, shift+left to move it back; right arrow to move the left border right, shift+right arrow to move back.';
        uilabel(g, 'Text', step8, 'FontSize', 13, ...
            'HorizontalAlignment', 'center', 'WordWrap', 'on');
        
        okbutton = uibutton(g, 'Text', 'OK');
        okbutton.Layout.Row = 11;
        okbutton.ButtonPushedFcn = @(src, event)okpush();
        
        function okpush() % close the help window on OK
            delete(fig);
        end
    end

% check for unique ordering of images
    function c = checkOrder(num, ddlist)
        c = 1;
        values = zeros(1, num);
        for k = 1:num
            dd = findobj(ddlist(k));
            values(k) = dd.Value;
        end
        check = unique(values);
        % check if the ordering is valid
        if size(check, 2) < size(values, 2)
            % disp('Invalid image order');
            c = 0;
        else
            % disp('Valid ordering');
        end
    end

% check if all axes have loaded images
    function c = checkLoad(num, axlist)
        c = 1;
        for k = 1:num
            handletochild = findobj(axlist(k), 'Type', 'image');
            if isempty(handletochild)
                c = 0;
                return
            end
        end
    end

% create an image display with the axis and buttons
    function obj = createImDisplay(grid, k)
        g = uigridlayout(grid, [2, 3]);
        g.RowHeight = {'1x', 25};
        obj = uiaxes(g);
        obj.Layout.Row = 1;
        obj.Layout.Column = [1 3];
        obj.Visible = 'off';
        obj.Toolbar.Visible = 'off';
        title(obj, strcat('Image', {' '}, int2str(k))); % add axis title
        % add load and unload buttons
        bL = uibutton(g, 'Text', 'Load new');
        bU = uibutton(g, 'Text', 'Clear');
        bdel = uibutton(g, 'Text', 'Delete');
        % set button callbacks
        bL.ButtonPushedFcn = @(src, event)openImage(obj);
        bU.ButtonPushedFcn = @(src, event)unloadImage(obj);
        bdel.ButtonPushedFcn = @(src, event)deleteAxes(obj);
    end

%% button callback functions

% save image as
    function saveAs(img)
        [filename, folder] = uiputfile('*.jpg', 'Save image as...');
        if filename ~= 0
            imwrite(img, fullfile(folder, filename));
        end
    end

% crop the image so that there is no black background
    function crop(ax, button, bsave)
        axes(ax);
        imshow(result, 'Parent', ax);
        hold(ax, 'on');
        [h, w, ~] = size(result);
        left = plot(ax, [1 1], [1 h], '-r');
        bot = plot(ax, [1 w], [h h], '-r');
        right = plot(ax, [w w], [h 1], '-r');
        top = plot(ax, [1 w], [1 1], '-r');
        % get figure handle
        fig = ax.Parent.Parent;
        fig.WindowKeyPressFcn = @(src, event)keyfunc(event, h, w);
        % button settings
        button.Text = 'Done';
        button.ButtonPushedFcn = @(src, event)donecropping(button, bsave);
        bsave.ButtonPushedFcn = @(src, event)saveAs(result(top.YData(1):bot.YData(1), left.XData(1):right.XData(1), :));
        
        % button callback
        function donecropping(button, bsave)
            delete(left); delete(right);
            delete(top); delete(bot);
            button.Text = 'Crop image';
            button.ButtonPushedFcn = @(src, event)crop(ax, button, bsave);
            bsave.ButtonPushedFcn = @(src, event)saveAs(result);
        end
        
        % register arrow keys to crop the image
        function keyfunc(event, h, w)
            % register the arrow keys + shift/control modifier
            % and move the red lines around
            if strcmp(event.Key, 'leftarrow')
                if strcmp(event.Modifier, 'shift') % move right line right
                    if right.XData(1) < w - 1
                        right.XData = right.XData + 2;
                    end
                else % right line left
                    if right.XData(1) - 1 > left.XData(1)
                        right.XData = right.XData - 2;
                    end
                end
            elseif strcmp(event.Key, 'rightarrow')
                if strcmp(event.Modifier, 'shift') % left line left
                    if left.XData(1) > 2
                        left.XData = left.XData - 2;
                    end
                else % left line right
                    if left.XData(1) < right.XData(1) - 1
                        left.XData = left.XData + 2;
                    end
                end
            elseif strcmp(event.Key, 'uparrow')
                if strcmp(event.Modifier, 'shift') % bottom line down
                    if bot.YData(1) < h - 1
                        bot.YData = bot.YData + 2;
                    end
                else % bottom line up
                    if bot.YData(1) - 1 > top.YData(1)
                        bot.YData = bot.YData - 2;
                    end
                end
            elseif strcmp(event.Key, 'downarrow')
                if strcmp(event.Modifier, 'shift') % top line up
                    if top.YData(1) > 2
                        top.YData = top.YData - 2;
                    end
                else % top line down
                    if top.YData(1) < bot.YData(1) - 1
                        top.YData = top.YData + 2;
                    end
                end
            end
        end
    end

% reset the application to the start up state
    function reset()
        % if empty, create the first two
        if Naxes==0
            addImage(); addImage();
        else
            % clear the first two, delete from the 3rd
            for a = Naxes:-1:1
                if a < 3
                    unloadImage(axislist(a));
                else
                    deleteAxes(axislist(a));
                end
            end
        end
    end

% delete axes, buttons and the small grid it was on
    function deleteAxes(axis)
        % get handles
        haxis = findobj(axis);
        grid = haxis.Parent;
        children = grid.Children;
        % disable components
        set(dds(axislist==axis), 'Enable', 'off');
        set(imlabels(axislist==axis), 'Enable', 'off');
        % delete from axislist
        axislist(axislist==axis) = [];
        % delete axis components and its grid
        delete(children);
        delete(grid);
        Naxes = Naxes - 1;
        % edit the dropdown lists
        editDropdown(dds, refdd, Naxes);
    end

% clear the loaded image from a given axis
    function unloadImage(axis)
        % get the image handle from axis
        handletochild = findobj(axislist(axislist==axis), 'Type', 'image');
        if ~isempty(handletochild)
            % delete the image, without deleting the axes
            delete(handletochild);
            images(axislist==axis) = [];
        end
    end

% function that corrects the dropdown list entries according to the number
% of images
    function editDropdown(ddlist, rdd, num)
        mylist = cellstr(string(1:num));
        % edit every list
        for f = 1:size(ddlist, 2)
            set(ddlist(f), 'Items', mylist);
        end
        % edit the reference dropdown
        set(rdd, 'Items', mylist);
    end

% add another image
    function addImage()
        if Naxes < maxaxes
            Naxes = Naxes + 1;
            % add new axes
            obj = createImDisplay(rightg, Naxes);
            axislist(Naxes) = obj;
            % edit the dropdown lists
            editDropdown(dds, refdd, Naxes);
            % enable ordering for the new axes
            set(imlabels(Naxes), 'Enable', 'on');
            set(dds(Naxes), 'Enable', 'on');
        else
            % report: too many images
            %             too_many_dialog();
            warndlg('You are trying to load too many images at once!', ...
                'Too many images', 'modal');
        end
    end

% open an image in axes
    function openImage(axis)
        % if there is an image loaded, open dialog to ask for reloading
        if ~isempty(images{axislist==axis})
            yes = reload_image(find(axislist==axis));
            if yes == 0
                return
            end
        end
        % open dialog window to select a file for opening
        [file, path] = uigetfile('*.*', 'Open an image', 'MultiSelect', 'off');
        % check for Cancel
        if ~isequal(file, 0) && ~isequal(path, 0)
            axes(axis);
            img = imread(fullfile(path, file)); % read the image
            himg = imshow(img, 'Parent', axis); % show and get handle
            set(himg, 'ButtonDownFcn', @(src, event)openImage(axis)); % set function handle to enable new image loading
            % save the image
            images(axislist==axis) = {img};
        end
        
    end

%% dialogs

% reload image dialog
    function r = reload_image(ind)
        r = 0;
        d = dialog('Position', [figSize/2 300 150], 'Name', 'Load new?');
        
        uicontrol('Parent', d, ...
            'Style', 'text', ...
            'Position', [0 80 300 40], ...
            'FontSize', 10, ...
            'String', strcat('Do you wish to load a new image to Image ', " ", int2str(ind), '?'));
        
        uicontrol('Parent', d, ...
            'String', 'Cancel', ...
            'Position', [60 30 75 30], ...
            'Callback', 'delete(gcf)');
        
        uicontrol('Parent', d, ...
            'Position', [165 30 75 30], ...
            'String', 'Yes', ...
            'Callback', @(src, event)buttonCallback);
        
        uiwait(d);
        function buttonCallback()
            r = 1;
            delete(gcf);
        end
    end

end
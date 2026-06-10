function [decout, d_codeword] = TPC_decoder(rev_data, n, k, H, p, alpha, beta, max_iter) 
 
% decoder parameters 
N = n+1; 
err_position = dlmread('err_p64.txt'); 
 
R = rev_data; 
for iter = 1 : max_iter 
    % ------------------------------------------- 
	% row decoding 
    % ------------------------------------------- 
	for row = 1 : N 
		row_data = rev_data(row, :);        
		[~, idx] = sort(abs(row_data(1 : n)));  % ???????? 
		lrp = idx(1:p);                         % least reliable position 
         
        hdata = double(row_data >= 0); 
		 
		subset_size = 0; 
		Omega = []; 
		dist = []; 
		 
		for i = 0 : 2^p-1 
			% test pattern 
			t = fliplr(de2bi(i, 4));				 
			test_pattern = zeros(1, N); 
			test_pattern(lrp) = t; 
             
			% test sequence 
			test_seq = mod(hdata + test_pattern, 2); 
			 
            % compute syndrome 
            syndrome = mod(H * test_seq(1:n)', 2)'; 
			syndrome = bi2de(fliplr(syndrome)); 
            if syndrome ~= 0 
				test_seq(err_position(syndrome)) = 1 - test_seq(err_position(syndrome)); 
			end 
			test_seq(N) = mod(sum(test_seq(1:n)), 2); 
			% if current codeword does not exist in Omega, add it 
			if subset_size > 0 
				flag = 0; 
				for j = 1 : subset_size 
					if test_seq == Omega(j,:) 
						flag = 1; 
						break; 
					end 
				end 
				if flag == 0 
					Omega = [Omega; test_seq]; 
					subset_size = subset_size + 1; 
				end 
			else 
				Omega = [Omega; test_seq]; 
				subset_size = subset_size + 1; 
			end 
		end	% end of test pattern 
		 
		% euclidean distance between each test sequence and receive data 
		for j = 1 : subset_size 
			dist = [dist, -1 * row_data * Omega(j,:)']; 
		end 
		[min_dist, min_idx] = min(dist); 
         
		% optimun codeword D 
		d_codeword = Omega(min_idx, :); 
         
		% extrinct information 
		ext_info = []; 
         
		% competing codewrod C 
		for j = 1 : N 
			c_codeword = +Inf; 
			for i = 1 : subset_size 
				if Omega(i,j) == 1 - d_codeword(j) && dist(i) < c_codeword 
					c_codeword = dist(i); 
				end 
			end 
			if c_codeword == +Inf 
				ext_info = [ext_info, (2 * d_codeword(j) - 1) * beta]; 
			else 
				ext_info = [ext_info, (2 * d_codeword(j) - 1) * (c_codeword - min_dist) - row_data(j)]; 
			end 
		end 
		rev_data(row, :) = R(row, :) + alpha * ext_info; 
	end % end of each row 
	 
	% get reliablity ratio of information bits 
	Rm = rev_data(1:k, 1:k) - R(1:k, 1:k); 
	 
    % ------------------------------------------- 
	% column decoding 
    % ------------------------------------------- 
	for col = 1 : N 
		col_data = rev_data(:, col); 
		col_data = col_data'; 
		hdata = double(col_data >= 0); 
		[~, lrp] = sort(abs(col_data(1:n))); 
		lrp = lrp(1:p); 
         
		subset_size = 0; 
		Omega = []; 
		dist = []; 
		 
		for i = 0 : 2^p-1 
			% test pattern 
			t = fliplr(de2bi(i, 4));				 
			test_pattern = zeros(1, N); 
			test_pattern(lrp) = t; 
			% test sequence 
			test_seq = mod(hdata + test_pattern, 2); 
			syndrome = mod(H * test_seq(1:n)', 2)'; 
			syndrome = bi2de(fliplr(syndrome)); 
			if syndrome ~= 0 
				test_seq(err_position(syndrome)) = 1 - test_seq(err_position(syndrome)); 
			end 
			test_seq(N) = mod(sum(test_seq(1:n)), 2); 
			% if current codeword does not exist in Omega, add it 
			if subset_size > 0 
				flag = 0; 
				for j = 1 : subset_size 
					if test_seq == Omega(j,:) 
						flag = 1; 
						break; 
					end 
				end 
				if flag == 0 
					Omega = [Omega; test_seq]; 
					subset_size = subset_size + 1; 
				end 
			else 
				Omega = [Omega; test_seq]; 
				subset_size = subset_size + 1; 
			end 
		end	% end of test pattern 
		 
		for j = 1 : subset_size 
			dist = [dist, -1 * col_data * Omega(j,:)']; 
		end 
		[min_dist, min_idx] = min(dist); 
		% optimun codeword D 
		d_codeword = Omega(min_idx, :); 
		% extrinct information 
		ext_info = []; 
		% competing codewrod C 
		for j = 1 : N 
			c_codeword = +Inf; 
			for i = 1 : subset_size 
				if Omega(i,j) == 1 - d_codeword(j) && dist(i) < c_codeword 
					c_codeword = dist(i); 
				end 
			end 
			if c_codeword == +Inf 
				ext_info = [ext_info, (2 * d_codeword(j) - 1) * beta]; 
			else 
				ext_info = [ext_info, (2 * d_codeword(j) - 1) * (c_codeword - min_dist) - col_data(j)]; 
			end 
		end 
		rev_data(:,col) = R(:,col) + alpha * ext_info'; 
	end % end of each column 
end % end of iteration 
Rm(1:k, 1:k) = Rm(1:k, 1:k) + rev_data(1:k, 1:k); 
decout = double(Rm >= 0);
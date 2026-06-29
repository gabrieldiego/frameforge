  always_ff @(posedge clk) begin
    if (!rst_n) begin
      input_error <= frame_reader_error_w || bitstream_writer_error_w;
      state_q <= ST_IDLE;
      m_axis_valid <= 1'b0;
      m_axis_data <= '0;
      m_axis_count <= '0;
      m_axis_last <= 1'b0;
      low_q <= 64'd0;
      rng_q <= 32'h8000;
      cnt_q <= -8'sd9;
      precarry_read_word_addr_q <= 12'd0;
      pending_push_valid_q <= 1'b0;
      pending_push_word_q <= 16'd0;
      payload_read_word_addr_q <= 12'd0;
      precarry_len_q <= 16'd0;
      tile_len_q <= 16'd0;
      payload_len_q <= 16'd0;
      payload_prefix_index_q <= 2'd0;
      seq_len_q <= 16'd0;
      stream_index_q <= 16'd0;
      frame_index_q <= 32'd0;
      input_frame_offset_q <= '0;
      output_byte_phase_q <= 4'd0;
      width_q <= 16'd0;
      height_q <= 16'd0;
      width_bits_q <= 5'd0;
      height_bits_q <= 5'd0;
      tile_cols_q <= 16'd1;
      tile_rows_q <= 16'd1;
      tile_count_q <= 16'd1;
      tile_index_q <= 16'd0;
      tile_col_q <= 16'd0;
      tile_row_q <= 16'd0;
      tile_width_q <= 16'd64;
      tile_height_q <= 16'd64;
      tile_input_index_q <= 32'd0;
      tile_input_active_q <= 1'b0;
      frame_palette_mode_q <= 1'b0;
      frame_ibc_mode_q <= 1'b0;
      seq_op_q <= 8'd0;
      seq_bits_left_q <= 7'd0;
      seq_value_q <= 64'd0;
      seq_bit_pos_q <= 16'd0;
      phase_q <= PHASE_INTRA;
      step_q <= 5'd0;
      palette_row_q <= 6'd0;
      palette_col_q <= 6'd0;
      palette_identity_row_ctx_q <= 2'd3;
      palette_mode_q <= 1'b0;
      lossy_420_mode_q <= 1'b0;
      leaf_luma_mode_q <= LUMA_MODE_DC;
      leaf_chroma_bdpcm_horz_q <= 1'b1;
      lossy420_luma_recon_q[0] <= 8'd128;
      lossy420_luma_recon_q[1] <= 8'd128;
      lossy420_luma_recon_q[2] <= 8'd128;
      lossy420_luma_recon_q[3] <= 8'd128;
      lossy420_luma_left_valid_q <= 16'd0;
      lossy420_luma_above_valid_q <= 16'd0;
      lossy420_u_left_valid_q <= 16'd0;
      lossy420_v_left_valid_q <= 16'd0;
      lossy420_u_above_valid_q <= 16'd0;
      lossy420_v_above_valid_q <= 16'd0;
      txb_index_q <= 16'd0;
      txb_width_q <= 16'd0;
      txb_count_q <= 16'd0;
      txb_local_row_q <= 5'd0;
      txb_local_col_q <= 5'd0;
      txb_prefetch_started_q <= 1'b0;
      txb_prefetch_done_q <= 1'b0;
      txb_prefetch_chroma_q <= 1'b0;
      txb_prefetch_plane_v_q <= 1'b0;
      txb_prefetch_index_q <= 2'd0;
      cached_v_valid_q <= 4'd0;
      cached_chroma_samples_valid_q <= 4'd0;
      left_edge_u_top_q <= 32'd0;
      left_edge_u_bottom_q <= 32'd0;
      left_edge_v_top_q <= 32'd0;
      left_edge_v_bottom_q <= 32'd0;
      left_edge_row_mi_q <= 5'd0;
      left_edge_col_mi_q <= 5'd0;
      left_edge_valid_q <= 1'b0;
      above_col0_u_q <= 32'd0;
      above_col0_v_q <= 32'd0;
      above_col0_row_mi_q <= 5'd0;
      above_col0_valid_q <= 1'b0;
      last_u_txb_nonzero_q <= 1'b0;
      visible_rows_mi_q <= 5'd0;
      visible_cols_mi_q <= 5'd0;
      block_row_mi_q <= 5'd0;
      block_col_mi_q <= 5'd0;
      block_w_mi_q <= 5'd0;
      block_h_mi_q <= 5'd0;
      partition_q <= PARTITION_NONE;
      partition_emit_step_q <= 1'b0;
      stack_sp_q <= 5'd0;
      finish_e_q <= 64'd0;
      finish_c_q <= 8'sd0;
      finish_s_q <= 8'sd0;
      carry_q <= 16'd0;
      carry_index_q <= 16'd0;
      output_last_q <= 1'b0;
      for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
        lossy420_luma_above_q[context_index_q] <= 8'd128;
        lossy420_luma_left_top_q[context_index_q] <= 8'd128;
        lossy420_luma_left_bottom_q[context_index_q] <= 8'd128;
        lossy420_luma_left_col_mi_q[context_index_q] <= 5'd0;
        lossy420_u_above_q[context_index_q] <= 8'd128;
        lossy420_v_above_q[context_index_q] <= 8'd128;
        lossy420_u_left_q[context_index_q] <= 8'd128;
        lossy420_v_left_q[context_index_q] <= 8'd128;
        lossy420_u_left_col_mi_q[context_index_q] <= 5'd0;
        lossy420_v_left_col_mi_q[context_index_q] <= 5'd0;
      end
    end else begin
      input_error <= 1'b0;
      if (luma_fetch_completed_w) begin
        cached_u_txb_samples_q[luma_fetch_cache_index_w] <= luma_fetch_u_txb_samples_w;
        cached_v_txb_samples_q[luma_fetch_cache_index_w] <= luma_fetch_v_txb_samples_w;
        cached_chroma_samples_valid_q[luma_fetch_cache_index_w] <= 1'b1;
      end
      if (chroma_fetch_completed_u_w) begin
        if (!cached_chroma_samples_valid_q[chroma_fetch_cache_index_w]) begin
          cached_v_txb_samples_q[chroma_fetch_cache_index_w] <= chroma_fetch_v_txb_samples_w;
          cached_chroma_samples_valid_q[chroma_fetch_cache_index_w] <= 1'b1;
        end
        cached_v_predictor_samples_q[chroma_fetch_cache_index_w] <= chroma_fetch_v_predictor_samples_w;
        cached_v_valid_q[chroma_fetch_cache_index_w] <= 1'b1;
      end
      if (start) begin
        input_error <= start_invalid_w;
        if (!start_invalid_w && state_q == ST_IDLE) begin
          state_q <= ST_TILE_START;
          m_axis_valid <= 1'b0;
          m_axis_count <= '0;
          m_axis_last <= 1'b0;
          width_q <= visible_width;
          height_q <= visible_height;
          width_bits_q <= width_bits_w;
          height_bits_q <= height_bits_w;
          seq_op_q <= 8'd0;
          seq_bits_left_q <= 7'd0;
          seq_value_q <= 64'd0;
          seq_bit_pos_q <= 16'd0;
          seq_len_q <= 16'd0;
          payload_len_q <= 16'd0;
          payload_prefix_index_q <= 2'd0;
          seq_mem_q[0] <= 8'd0;
          seq_mem_q[1] <= 8'd0;
          seq_mem_q[2] <= 8'd0;
          seq_mem_q[3] <= 8'd0;
          seq_mem_q[4] <= 8'd0;
          seq_mem_q[5] <= 8'd0;
          seq_mem_q[6] <= 8'd0;
          seq_mem_q[7] <= 8'd0;
          seq_mem_q[8] <= 8'd0;
          seq_mem_q[9] <= 8'd0;
          seq_mem_q[10] <= 8'd0;
          seq_mem_q[11] <= 8'd0;
          seq_mem_q[12] <= 8'd0;
          seq_mem_q[13] <= 8'd0;
          seq_mem_q[14] <= 8'd0;
          seq_mem_q[15] <= 8'd0;
          low_q <= 64'd0;
          rng_q <= 32'h8000;
          cnt_q <= -8'sd9;
          precarry_read_word_addr_q <= 12'd0;
          pending_push_valid_q <= 1'b0;
          pending_push_word_q <= 16'd0;
          precarry_len_q <= 16'd0;
          tile_len_q <= 16'd0;
          stream_index_q <= 16'd0;
          frame_index_q <= 32'd0;
          input_frame_offset_q <= '0;
          output_byte_phase_q <= 4'd0;
          tile_cols_q <= tile_cols_w;
          tile_rows_q <= tile_rows_w;
          tile_count_q <= tile_count_w;
          tile_index_q <= 16'd0;
          tile_col_q <= 16'd0;
          tile_row_q <= 16'd0;
          tile_width_q <= (tile_cols_w == 16'd1) ? visible_width : 16'd64;
          tile_height_q <= (tile_rows_w == 16'd1) ? visible_height : 16'd64;
          tile_input_index_q <= 32'd0;
          tile_input_active_q <= 1'b0;
          frame_palette_mode_q <= 1'b0;
          frame_ibc_mode_q <= 1'b0;
          phase_q <= PHASE_INTRA;
          step_q <= 5'd0;
          palette_row_q <= 6'd0;
          palette_col_q <= 6'd0;
          palette_identity_row_ctx_q <= 2'd3;
          palette_mode_q <= 1'b0;
          lossy_420_mode_q <= 1'b0;
          leaf_luma_mode_q <= LUMA_MODE_DC;
          leaf_chroma_bdpcm_horz_q <= 1'b1;
          lossy420_luma_recon_q[0] <= 8'd128;
          lossy420_luma_recon_q[1] <= 8'd128;
          lossy420_luma_recon_q[2] <= 8'd128;
          lossy420_luma_recon_q[3] <= 8'd128;
          lossy420_luma_left_valid_q <= 16'd0;
          lossy420_luma_above_valid_q <= 16'd0;
          lossy420_u_left_valid_q <= 16'd0;
          lossy420_v_left_valid_q <= 16'd0;
          lossy420_u_above_valid_q <= 16'd0;
          lossy420_v_above_valid_q <= 16'd0;
          txb_index_q <= 16'd0;
          txb_width_q <= 16'd0;
          txb_count_q <= 16'd0;
          txb_local_row_q <= 5'd0;
          txb_local_col_q <= 5'd0;
          txb_prefetch_started_q <= 1'b0;
          txb_prefetch_done_q <= 1'b0;
          txb_prefetch_chroma_q <= 1'b0;
          txb_prefetch_plane_v_q <= 1'b0;
          txb_prefetch_index_q <= 2'd0;
          cached_v_valid_q <= 4'd0;
          cached_chroma_samples_valid_q <= 4'd0;
          left_edge_u_top_q <= 32'd0;
          left_edge_u_bottom_q <= 32'd0;
          left_edge_v_top_q <= 32'd0;
          left_edge_v_bottom_q <= 32'd0;
          left_edge_row_mi_q <= 5'd0;
          left_edge_col_mi_q <= 5'd0;
          left_edge_valid_q <= 1'b0;
          above_col0_u_q <= 32'd0;
          above_col0_v_q <= 32'd0;
          above_col0_row_mi_q <= 5'd0;
          above_col0_valid_q <= 1'b0;
          last_u_txb_nonzero_q <= 1'b0;
          visible_rows_mi_q <= visible_rows_mi_w;
          visible_cols_mi_q <= visible_cols_mi_w;
          block_row_mi_q <= 5'd0;
          block_col_mi_q <= 5'd0;
          block_w_mi_q <= 5'd16;
          block_h_mi_q <= 5'd16;
          partition_q <= PARTITION_NONE;
          partition_emit_step_q <= 1'b0;
          stack_sp_q <= 5'd0;
          output_last_q <= 1'b0;
          state_q <= ST_TILE_START;
        end
      end else begin
        // AV2 overlap path: pixel ingress is a sideband update. It must not
        // steal cycles from entropy normalization or symbol emission once the
        // tile starts encoding from block-ready analyzer descriptors.
        if (input_fire_w) begin
          tile_input_index_q <= tile_input_index_q + {28'd0, input_fire_count_w};
        end
        if (palette_analyzer_done_w) begin
          tile_input_active_q <= 1'b0;
        end
        if (input_fire_error_w) begin
          input_error <= 1'b1;
          tile_input_active_q <= 1'b0;
          state_q <= ST_IDLE;
        end else if (pending_push_valid_q) begin
          precarry_len_q <= precarry_len_q + 16'd1;
          pending_push_valid_q <= 1'b0;
          if (txb_prefetch_started_q && txb_prefetch_fetch_done_w) begin
            txb_prefetch_done_q <= 1'b1;
          end
        end else begin
          case (state_q)
          ST_IDLE: begin
            m_axis_valid <= 1'b0;
            m_axis_count <= '0;
            m_axis_last <= 1'b0;
          end
          ST_TILE_START: begin
            tile_input_index_q <= 32'd0;
            tile_input_active_q <= 1'b1;
            state_q <= ST_INPUT_READ;
          end
          ST_INPUT_READ: begin
            if (palette_analyzer_done_w) begin
              tile_input_active_q <= 1'b0;
            end
            if (tile_entropy_start_ready_w) begin
              if (palette_analyzer_unsupported_w) begin
                input_error <= 1'b1;
                state_q <= ST_IDLE;
              end else begin
                palette_mode_q <= tile_entropy_palette_mode_w;
                lossy_420_mode_q <= tile_entropy_lossy420_mode_w;
                frame_palette_mode_q <= frame_palette_mode_q | tile_entropy_palette_mode_w;
                // AV2 v1.0.0 read_intrabc_params()/read_intra_frame_mode_info():
                // allow_intrabc is a frame-header decision, while the MVP RTL
                // enables the syntax as soon as nonblack 4:4:4 palette content
                // is observed. Each leaf still independently writes use_intrabc
                // from the streaming hash matcher.
                frame_ibc_mode_q <= frame_ibc_mode_q | tile_entropy_ibc_mode_w;
                low_q <= 64'd0;
                rng_q <= 32'h8000;
                cnt_q <= -8'sd9;
                precarry_read_word_addr_q <= 12'd0;
                pending_push_valid_q <= 1'b0;
                pending_push_word_q <= 16'd0;
                precarry_len_q <= 16'd0;
                tile_len_q <= 16'd0;
                phase_q <= tile_entropy_ibc_mode_w ? PHASE_INTRABC : PHASE_INTRA;
                step_q <= 5'd0;
                palette_row_q <= 6'd0;
                palette_col_q <= 6'd0;
                palette_identity_row_ctx_q <= 2'd3;
                leaf_luma_mode_q <= LUMA_MODE_DC;
                leaf_chroma_bdpcm_horz_q <= 1'b1;
                lossy420_luma_recon_q[0] <= 8'd128;
                lossy420_luma_recon_q[1] <= 8'd128;
                lossy420_luma_recon_q[2] <= 8'd128;
                lossy420_luma_recon_q[3] <= 8'd128;
                lossy420_luma_left_valid_q <= 16'd0;
                lossy420_luma_above_valid_q <= 16'd0;
                lossy420_u_left_valid_q <= 16'd0;
                lossy420_v_left_valid_q <= 16'd0;
                lossy420_u_above_valid_q <= 16'd0;
                lossy420_v_above_valid_q <= 16'd0;
                txb_index_q <= 16'd0;
                txb_width_q <= 16'd0;
                txb_count_q <= 16'd0;
                txb_local_row_q <= 5'd0;
                txb_local_col_q <= 5'd0;
                txb_prefetch_started_q <= 1'b0;
                txb_prefetch_done_q <= 1'b0;
                txb_prefetch_chroma_q <= 1'b0;
                txb_prefetch_plane_v_q <= 1'b0;
                txb_prefetch_index_q <= 2'd0;
                cached_v_valid_q <= 4'd0;
                cached_chroma_samples_valid_q <= 4'd0;
                left_edge_u_top_q <= 32'd0;
                left_edge_u_bottom_q <= 32'd0;
                left_edge_v_top_q <= 32'd0;
                left_edge_v_bottom_q <= 32'd0;
                left_edge_row_mi_q <= 5'd0;
                left_edge_col_mi_q <= 5'd0;
                left_edge_valid_q <= 1'b0;
                above_col0_u_q <= 32'd0;
                above_col0_v_q <= 32'd0;
                above_col0_row_mi_q <= 5'd0;
                above_col0_valid_q <= 1'b0;
                last_u_txb_nonzero_q <= 1'b0;
                visible_rows_mi_q <= visible_rows_mi_w;
                visible_cols_mi_q <= visible_cols_mi_w;
                block_row_mi_q <= 5'd0;
                block_col_mi_q <= 5'd0;
                block_w_mi_q <= 5'd16;
                block_h_mi_q <= 5'd16;
                partition_q <= PARTITION_NONE;
                partition_emit_step_q <= 1'b0;
                stack_sp_q <= 5'd0;
                for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                  lossy420_luma_above_q[context_index_q] <= 8'd128;
                  lossy420_luma_left_top_q[context_index_q] <= 8'd128;
                  lossy420_luma_left_bottom_q[context_index_q] <= 8'd128;
                  lossy420_luma_left_col_mi_q[context_index_q] <= 5'd0;
                  lossy420_u_above_q[context_index_q] <= 8'd128;
                  lossy420_v_above_q[context_index_q] <= 8'd128;
                  lossy420_u_left_q[context_index_q] <= 8'd128;
                  lossy420_v_left_q[context_index_q] <= 8'd128;
                  lossy420_u_left_col_mi_q[context_index_q] <= 5'd0;
                  lossy420_v_left_col_mi_q[context_index_q] <= 5'd0;
                end
                state_q <= (tile_index_q == 16'd0) ? ST_SEQ_LOAD : ST_LOAD_BLOCK;
              end
            end
          end
          ST_SEQ_LOAD: begin
            if (seq_op_q == 8'd18) begin
              seq_len_q <= (seq_bit_pos_q + 16'd7) >> 3;
              state_q <= ST_LOAD_BLOCK;
            end else begin
              seq_value_q <= seq_load_value_w;
              seq_bits_left_q <= seq_load_bits_w;
              state_q <= ST_SEQ_WRITE;
            end
          end
          ST_SEQ_WRITE: begin
            for (seq_write_i = 0; seq_write_i < 8; seq_write_i = seq_write_i + 1) begin
              if (seq_write_i[3:0] < seq_write_step_w) begin
                seq_mem_q[seq_bit_pos_q[15:3]]
                  [7 - (seq_bit_pos_q[2:0] + seq_write_i[2:0])] <=
                    seq_value_q[seq_bits_left_q - {3'd0, seq_write_i[3:0]} - 7'd1];
              end
            end
            seq_bit_pos_q <= seq_bit_pos_q + {12'd0, seq_write_step_w};
            if (seq_bits_left_q == {3'd0, seq_write_step_w}) begin
              seq_bits_left_q <= 7'd0;
              seq_op_q <= seq_op_q + 8'd1;
              state_q <= ST_SEQ_LOAD;
            end else begin
              seq_bits_left_q <= seq_bits_left_q - {3'd0, seq_write_step_w};
            end
          end
          ST_LOAD_BLOCK: begin
            if (!block_visible_w) begin
              if (stack_sp_q != 5'd0) begin
                block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                stack_sp_q <= stack_sp_q - 5'd1;
              end else begin
                state_q <= ST_FINISH_INIT;
              end
            end else begin
              partition_q <= chosen_partition_w;
              partition_emit_step_q <= 1'b0;
              state_q <= ST_PARTITION;
            end
          end
          ST_PARTITION: begin
            if (op_valid_w) begin
              if (norm_push_count_w != 2'd0) begin
                precarry_len_q <= precarry_len_q + 16'd1;
              end
              if (norm_push_count_w == 2'd2) begin
                pending_push_valid_q <= 1'b1;
                pending_push_word_q <= norm_push1_w;
              end
              low_q <= norm_low_w;
              rng_q <= norm_rng_w;
              cnt_q <= norm_cnt_w;

              if (partition_emit_do_split_w && partition_need_rect_w) begin
                partition_emit_step_q <= 1'b1;
              end else if (partition_q == PARTITION_NONE) begin
                phase_q <= frame_ibc_mode_q ? PHASE_INTRABC : PHASE_INTRA;
                step_q <= 5'd0;
                palette_row_q <= 6'd0;
                palette_col_q <= 6'd0;
                palette_identity_row_ctx_q <= 2'd3;
                txb_index_q <= 16'd0;
                txb_local_row_q <= 5'd0;
                txb_local_col_q <= 5'd0;
                last_u_txb_nonzero_q <= 1'b0;
                txb_width_q <= txb_width_w;
                txb_count_q <= txb_count_w;
                txb_prefetch_started_q <= 1'b0;
                txb_prefetch_done_q <= 1'b0;
                txb_prefetch_plane_v_q <= 1'b0;
                txb_prefetch_index_q <= 2'd0;
                cached_v_valid_q <= 4'd0;
                cached_chroma_samples_valid_q <= 4'd0;
                lossy420_luma_recon_q[0] <= 8'd128;
                lossy420_luma_recon_q[1] <= 8'd128;
                lossy420_luma_recon_q[2] <= 8'd128;
                lossy420_luma_recon_q[3] <= 8'd128;
                if (current_leaf_ready_w) begin
                  state_q <= frame_ibc_mode_q ? ST_LEAF :
                             (palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF);
                end else begin
                  state_q <= ST_LEAF_WAIT;
                end
              end else if (partition_q == PARTITION_HORZ) begin
                stack_row_mi_q[stack_sp_q] <= block_row_mi_q + block_half_h_mi_w;
                stack_col_mi_q[stack_sp_q] <= block_col_mi_q;
                stack_w_mi_q[stack_sp_q] <= block_w_mi_q;
                stack_h_mi_q[stack_sp_q] <= block_half_h_mi_w;
                stack_sp_q <= stack_sp_q + 5'd1;
                block_h_mi_q <= block_half_h_mi_w;
                state_q <= ST_LOAD_BLOCK;
              end else begin
                stack_row_mi_q[stack_sp_q] <= block_row_mi_q;
                stack_col_mi_q[stack_sp_q] <= block_col_mi_q + block_half_w_mi_w;
                stack_w_mi_q[stack_sp_q] <= block_half_w_mi_w;
                stack_h_mi_q[stack_sp_q] <= block_h_mi_q;
                stack_sp_q <= stack_sp_q + 5'd1;
                block_w_mi_q <= block_half_w_mi_w;
                state_q <= ST_LOAD_BLOCK;
              end
            end else if (partition_q == PARTITION_NONE) begin
              phase_q <= frame_ibc_mode_q ? PHASE_INTRABC : PHASE_INTRA;
              step_q <= 5'd0;
              palette_row_q <= 6'd0;
              palette_col_q <= 6'd0;
              palette_identity_row_ctx_q <= 2'd3;
              leaf_luma_mode_q <= LUMA_MODE_DC;
              leaf_chroma_bdpcm_horz_q <= 1'b1;
              txb_index_q <= 16'd0;
              txb_local_row_q <= 5'd0;
              txb_local_col_q <= 5'd0;
              last_u_txb_nonzero_q <= 1'b0;
              txb_width_q <= txb_width_w;
              txb_count_q <= txb_count_w;
              txb_prefetch_started_q <= 1'b0;
              txb_prefetch_done_q <= 1'b0;
              txb_prefetch_plane_v_q <= 1'b0;
              txb_prefetch_index_q <= 2'd0;
              cached_v_valid_q <= 4'd0;
              cached_chroma_samples_valid_q <= 4'd0;
              lossy420_luma_recon_q[0] <= 8'd128;
              lossy420_luma_recon_q[1] <= 8'd128;
              lossy420_luma_recon_q[2] <= 8'd128;
              lossy420_luma_recon_q[3] <= 8'd128;
              if (current_leaf_ready_w) begin
                state_q <= frame_ibc_mode_q ? ST_LEAF :
                           (palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF);
              end else begin
                state_q <= ST_LEAF_WAIT;
              end
            end else if (partition_q == PARTITION_HORZ) begin
              stack_row_mi_q[stack_sp_q] <= block_row_mi_q + block_half_h_mi_w;
              stack_col_mi_q[stack_sp_q] <= block_col_mi_q;
              stack_w_mi_q[stack_sp_q] <= block_w_mi_q;
              stack_h_mi_q[stack_sp_q] <= block_half_h_mi_w;
              stack_sp_q <= stack_sp_q + 5'd1;
              block_h_mi_q <= block_half_h_mi_w;
              state_q <= ST_LOAD_BLOCK;
            end else begin
              stack_row_mi_q[stack_sp_q] <= block_row_mi_q;
              stack_col_mi_q[stack_sp_q] <= block_col_mi_q + block_half_w_mi_w;
              stack_w_mi_q[stack_sp_q] <= block_half_w_mi_w;
              stack_h_mi_q[stack_sp_q] <= block_h_mi_q;
              stack_sp_q <= stack_sp_q + 5'd1;
              block_w_mi_q <= block_half_w_mi_w;
              state_q <= ST_LOAD_BLOCK;
            end
          end
          ST_LEAF_WAIT: begin
            if (current_leaf_ready_w) begin
              state_q <= frame_ibc_mode_q ? ST_LEAF :
                         (palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF);
            end
          end
          ST_PALETTE_QUERY: begin
            if (palette_query_done_w) begin
              leaf_luma_mode_q <= palette_luma_mode_w;
              leaf_chroma_bdpcm_horz_q <= palette_chroma_bdpcm_horz_w;
              state_q <= ST_LEAF;
            end else if (!palette_mode_q) begin
              state_q <= ST_LEAF;
            end
          end
          ST_LEAF: begin
            if (txb_prefetch_luma_start_w || txb_prefetch_chroma_start_w) begin
              txb_prefetch_started_q <= 1'b1;
              txb_prefetch_done_q <= 1'b0;
              txb_prefetch_chroma_q <= txb_prefetch_chroma_start_w;
              txb_prefetch_plane_v_q <= chroma_fetch_req_plane_v_w;
              txb_prefetch_index_q <=
                (txb_prefetch_cross_phase_w || txb_prefetch_first_luma_w) ?
                  2'd0 : (txb_index_q[1:0] + 2'd1);
            end else if (txb_prefetch_started_q && txb_prefetch_fetch_done_w) begin
              txb_prefetch_done_q <= 1'b1;
            end

            if (op_valid_w) begin
              if (norm_push_count_w != 2'd0) begin
                precarry_len_q <= precarry_len_q + 16'd1;
              end
              if (norm_push_count_w == 2'd2) begin
                pending_push_valid_q <= 1'b1;
                pending_push_word_q <= norm_push1_w;
              end
              low_q <= norm_low_w;
              rng_q <= norm_rng_w;
              cnt_q <= norm_cnt_w;

              if (phase_q == PHASE_INTRABC) begin
                if (step_q == 5'd0 && !ibc_use_copy_w) begin
                  phase_q <= PHASE_INTRA;
                  step_q <= 5'd0;
                  leaf_luma_mode_q <= LUMA_MODE_DC;
                  leaf_chroma_bdpcm_horz_q <= 1'b1;
                  state_q <= palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF;
                end else if ((step_q == 5'd3 && ibc_drl_idx_w == 2'd0) ||
                             (step_q == 5'd4 && ibc_drl_idx_w == 2'd1) ||
                             (step_q == 5'd5)) begin
                  // AV2 v1.0.0 read_intra_frame_mode_info()/read_skip_txfm():
                  // an IntraBC leaf updates use_intrabc and skip_txfm
                  // neighbor contexts in ff_av2_ibc_context_bank. This also
                  // clears the TXB contexts for the copied leaf via the
                  // context bank. TODO(av2 entropy): if
                  // SDP, chroma partition trees, or non-8x8 leaves are
                  // enabled, mirror the AVM MB_MODE_INFO availability rules
                  // instead of this shared fixed-leaf context map.
                  if (stack_sp_q != 5'd0) begin
                    block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                    block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                    block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                    block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                    stack_sp_q <= stack_sp_q - 5'd1;
                    state_q <= ST_LOAD_BLOCK;
                  end else begin
                    state_q <= ST_FINISH_INIT;
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else if (op_last_w) begin
                txb_prefetch_started_q <= 1'b0;
                txb_prefetch_done_q <= 1'b0;
                state_q <= ST_FINISH_INIT;
              end else if (phase_q == PHASE_INTRA) begin
                if (step_q == 5'd2 && !leaf_fsc_symbol_w) begin
                  step_q <= 5'd4;
                end else if (step_q == 5'd5) begin
                  phase_q <= leaf_luma_palette_w ? PHASE_PALETTE_HEADER : PHASE_Y_COEFF;
                  step_q <= 5'd0;
                  palette_row_q <= 6'd0;
                  palette_col_q <= 6'd0;
                  palette_identity_row_ctx_q <= 2'd3;
                  txb_index_q <= 16'd0;
                  txb_local_row_q <= 5'd0;
                  txb_local_col_q <= 5'd0;
                  last_u_txb_nonzero_q <= 1'b0;
                  if (residual_mode_w && !leaf_luma_palette_w) begin
                    if (lossy_420_mode_q || txb_prefetch_done_q) begin
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      state_q <= ST_LEAF;
                    end else begin
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      state_q <= ST_CHROMA_FETCH;
                    end
                  end else if (!residual_mode_w) begin
                    txb_prefetch_started_q <= 1'b0;
                    txb_prefetch_done_q <= 1'b0;
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else if (phase_q == PHASE_PALETTE_HEADER) begin
                if (palette_header_last_step_w) begin
                  phase_q <= PHASE_PALETTE_MAP;
                  step_q <= 5'd0;
                  palette_row_q <= 6'd0;
                  palette_col_q <= 6'd0;
                  palette_identity_row_ctx_q <= 2'd3;
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else if (phase_q == PHASE_PALETTE_MAP) begin
                if (step_q == 5'd0) begin
                  step_q <= 5'd1;
                end else if (step_q == 5'd1) begin
                  palette_identity_row_ctx_q <= palette_identity_row_flag_w;
                  if (palette_map_token_required_w) begin
                    step_q <= 5'd2;
                  end else if (palette_row_q == 6'd7) begin
                    phase_q <= PHASE_Y_COEFF;
                    step_q <= 5'd0;
                    txb_index_q <= 16'd0;
                    txb_local_row_q <= 5'd0;
                    txb_local_col_q <= 5'd0;
                    if (txb_prefetch_done_q) begin
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      state_q <= ST_LEAF;
                    end else begin
                      txb_prefetch_started_q <= txb_prefetch_started_q;
                      txb_prefetch_done_q <= txb_prefetch_done_q;
                      state_q <= ST_CHROMA_FETCH;
                    end
                  end else begin
                    palette_row_q <= palette_row_q + 6'd1;
                    palette_col_q <= 6'd0;
                    step_q <= 5'd1;
                  end
                end else if (palette_identity_row_flag_w == 2'd0 && palette_col_q != 6'd7) begin
                  palette_col_q <= palette_col_q + 6'd1;
                  step_q <= 5'd2;
                end else if (palette_row_q == 6'd7) begin
                  phase_q <= PHASE_Y_COEFF;
                  step_q <= 5'd0;
                  txb_index_q <= 16'd0;
                  txb_local_row_q <= 5'd0;
                  txb_local_col_q <= 5'd0;
                  if (txb_prefetch_done_q) begin
                    txb_prefetch_started_q <= 1'b0;
                    txb_prefetch_done_q <= 1'b0;
                    state_q <= ST_LEAF;
                  end else begin
                    txb_prefetch_started_q <= txb_prefetch_started_q;
                    txb_prefetch_done_q <= txb_prefetch_done_q;
                    state_q <= ST_CHROMA_FETCH;
                  end
                end else begin
                  palette_row_q <= palette_row_q + 6'd1;
                  palette_col_q <= 6'd0;
                  step_q <= 5'd1;
                end
              end else if (phase_q == PHASE_Y_COEFF) begin
                if ((residual_mode_w && luma_residual_txb_done_w) || (!residual_mode_w && step_q == 5'd8)) begin
                  if (lossy_420_mode_q) begin
                    lossy420_luma_recon_q[txb_index_q[1:0]] <=
                      lossy420_luma_residual_recon_sample_w;
                    lossy420_luma_above_q[txb_col_w[3:0]] <=
                      lossy420_luma_residual_recon_sample_w;
                    lossy420_luma_above_valid_q[txb_col_w[3:0]] <= 1'b1;
                    if (txb_index_q[0]) begin
                      if (txb_index_q[1]) begin
                        lossy420_luma_left_bottom_q[lossy420_luma_left_row_index_w] <=
                          lossy420_luma_residual_recon_sample_w;
                        lossy420_luma_left_valid_q[lossy420_luma_left_row_index_w] <= 1'b1;
                        lossy420_luma_left_col_mi_q[lossy420_luma_left_row_index_w] <=
                          block_col_mi_q;
                      end else begin
                        lossy420_luma_left_top_q[lossy420_luma_left_row_index_w] <=
                          lossy420_luma_residual_recon_sample_w;
                      end
                    end
                  end
                  if (txb_index_q == (txb_count_q - 16'd1)) begin
                    phase_q <= PHASE_U_COEFF;
                    step_q <= 5'd0;
                    txb_index_q <= 16'd0;
                    txb_width_q <= chroma_txb_width_w;
                    txb_count_q <= chroma_txb_count_w;
                    txb_local_row_q <= 5'd0;
                    txb_local_col_q <= 5'd0;
                    txb_prefetch_started_q <= 1'b0;
                    txb_prefetch_done_q <= 1'b0;
                    last_u_txb_nonzero_q <= 1'b0;
                    if (residual_mode_w) begin
                      if (lossy_420_mode_q ||
                          (txb_prefetch_done_q && txb_prefetch_chroma_q && !txb_prefetch_plane_v_q) ||
                          chroma_fetch_req_ready_w) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_LEAF;
                      end else begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_CHROMA_FETCH;
                      end
                    end
                  end else begin
                    step_q <= 5'd0;
                    txb_index_q <= txb_index_q + 16'd1;
                    if (txb_local_col_q == (txb_width_q[4:0] - 5'd1)) begin
                      txb_local_col_q <= 5'd0;
                      txb_local_row_q <= txb_local_row_q + 5'd1;
                    end else begin
                      txb_local_col_q <= txb_local_col_q + 5'd1;
                    end
                    if (residual_mode_w) begin
                      if (lossy_420_mode_q || (txb_prefetch_done_q && !txb_prefetch_chroma_q)) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_LEAF;
                      end else begin
                        state_q <= ST_CHROMA_FETCH;
                      end
                    end
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else begin
                if ((residual_mode_w && chroma_bdpcm_txb_done_w) || (!residual_mode_w && step_q == 5'd7)) begin
                  if (residual_mode_w) begin
                    if (phase_q == PHASE_U_COEFF) begin
                      last_u_txb_nonzero_q <= chroma_bdpcm_txb_nonzero_w;
                      if (lossy_420_mode_q) begin
                        lossy420_u_above_q[txb_col_w[3:0]] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_u_above_valid_q[txb_col_w[3:0]] <= 1'b1;
                        lossy420_u_left_q[lossy420_chroma_left_row_index_w] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_u_left_col_mi_q[lossy420_chroma_left_row_index_w] <=
                          txb_col_w[4:0];
                        lossy420_u_left_valid_q[lossy420_chroma_left_row_index_w] <= 1'b1;
                      end
                    end else begin
                      if (lossy_420_mode_q) begin
                        lossy420_v_above_q[txb_col_w[3:0]] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_v_above_valid_q[txb_col_w[3:0]] <= 1'b1;
                        lossy420_v_left_q[lossy420_chroma_left_row_index_w] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_v_left_col_mi_q[lossy420_chroma_left_row_index_w] <=
                          txb_col_w[4:0];
                        lossy420_v_left_valid_q[lossy420_chroma_left_row_index_w] <= 1'b1;
                      end
                    end
                  end
                  if (txb_index_q == (txb_count_q - 16'd1)) begin
                    if (phase_q == PHASE_U_COEFF) begin
                      phase_q <= PHASE_V_COEFF;
                      step_q <= 5'd0;
                      txb_index_q <= 16'd0;
                      txb_width_q <= chroma_txb_width_w;
                      txb_count_q <= chroma_txb_count_w;
                      txb_local_row_q <= 5'd0;
                      txb_local_col_q <= 5'd0;
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      if (residual_mode_w) begin
                        if (lossy_420_mode_q ||
                            (txb_prefetch_done_q && txb_prefetch_chroma_q && txb_prefetch_plane_v_q) ||
                            chroma_fetch_req_ready_w) begin
                          txb_prefetch_started_q <= 1'b0;
                          txb_prefetch_done_q <= 1'b0;
                          state_q <= ST_LEAF;
                        end else begin
                          txb_prefetch_started_q <= 1'b0;
                          txb_prefetch_done_q <= 1'b0;
                          state_q <= ST_CHROMA_FETCH;
                        end
                      end
                    end else begin
                      left_edge_u_top_q <= current_u_right_edge_top_w;
                      left_edge_u_bottom_q <= current_u_right_edge_bottom_w;
                      left_edge_v_top_q <= current_v_right_edge_top_w;
                      left_edge_v_bottom_q <= current_v_right_edge_bottom_w;
                      left_edge_row_mi_q <= block_row_mi_q;
                      left_edge_col_mi_q <= block_col_mi_q;
                      left_edge_valid_q <=
                        cached_chroma_samples_valid_q[2'd1] &&
                        cached_chroma_samples_valid_q[2'd3];
                      if (block_col_mi_q == 5'd0) begin
                        above_col0_u_q <= current_u_col0_above_edge_w;
                        above_col0_v_q <= current_v_col0_above_edge_w;
                        above_col0_row_mi_q <= block_row_mi_q;
                        above_col0_valid_q <= cached_chroma_samples_valid_q[2'd2];
                      end
                      if (stack_sp_q != 5'd0) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                        block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                        block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                        block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                        stack_sp_q <= stack_sp_q - 5'd1;
                        state_q <= ST_LOAD_BLOCK;
                      end else begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_FINISH_INIT;
                      end
                    end
                  end else begin
                    step_q <= 5'd0;
                    txb_index_q <= txb_index_q + 16'd1;
                    if (txb_local_col_q == (txb_width_q[4:0] - 5'd1)) begin
                      txb_local_col_q <= 5'd0;
                      txb_local_row_q <= txb_local_row_q + 5'd1;
                    end else begin
                      txb_local_col_q <= txb_local_col_q + 5'd1;
                    end
                    if (residual_mode_w) begin
                      if (lossy_420_mode_q ||
                          (txb_prefetch_done_q && txb_prefetch_chroma_q) ||
                          chroma_fetch_req_ready_w) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_LEAF;
                      end else begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_CHROMA_FETCH;
                      end
                    end
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end
            end
          end
          ST_CHROMA_FETCH: begin
            if (((phase_q == PHASE_Y_COEFF) &&
                 ((txb_prefetch_done_q && !txb_prefetch_chroma_q) || luma_fetch_done_w)) ||
                ((phase_q == PHASE_U_COEFF) &&
                 ((txb_prefetch_done_q && txb_prefetch_chroma_q && !txb_prefetch_plane_v_q) ||
                  chroma_fetch_done_w ||
                  chroma_fetch_current_cache_hit_w)) ||
                ((phase_q == PHASE_V_COEFF) &&
                 ((txb_prefetch_done_q && txb_prefetch_chroma_q && txb_prefetch_plane_v_q) ||
                  chroma_fetch_done_w ||
                  chroma_fetch_current_cache_hit_w))) begin
              step_q <= 5'd0;
              txb_prefetch_started_q <= 1'b0;
              txb_prefetch_done_q <= 1'b0;
              state_q <= ST_LEAF;
            end
          end
          ST_FINISH_INIT: begin
            finish_e_q <= ((low_q + 64'h3fff) & ~64'h3fff) | 64'h4000;
            finish_c_q <= cnt_q;
            finish_s_q <= cnt_q + 8'sd10;
            state_q <= ST_FINISH_PUSH;
          end
          ST_FINISH_PUSH: begin
            if (finish_s_q > 8'sd0) begin
              precarry_len_q <= precarry_len_q + 16'd1;
              if ((finish_c_q + 8'sd16) >= 8'sd64) begin
                finish_e_q <= 64'd0;
              end else if ((finish_c_q + 8'sd16) <= 8'sd0) begin
                finish_e_q <= finish_e_q;
              end else begin
                finish_e_q <=
                  finish_e_q & ((64'd1 << (finish_c_q[5:0] + 6'd16)) - 64'd1);
              end
              finish_c_q <= finish_c_q - 8'sd8;
              finish_s_q <= finish_s_q - 8'sd8;
            end else begin
              carry_q <= 16'd0;
              carry_index_q <= precarry_len_q - 16'd1;
              precarry_read_word_addr_q <= (precarry_len_q - 16'd1) >> 4;
              tile_len_q <= precarry_len_q;
              state_q <= ST_CARRY_READ;
            end
          end
          ST_CARRY_READ: begin
            precarry_read_word_addr_q <= carry_read_after_current_word_addr_w;
            state_q <= ST_CARRY_WRITE;
          end
          ST_CARRY_WRITE: begin
            if (carry_done_after_step_w) begin
              carry_q <= carry_after_step_w;
              payload_prefix_index_q <= 2'd0;
              precarry_read_word_addr_q <= 12'd0;
              state_q <= ST_PAYLOAD_PREFIX;
            end else begin
              carry_q <= carry_after_step_w;
              carry_index_q <= carry_index_after_step_w;
              precarry_read_word_addr_q <= carry_read_after_next_word_addr_w;
              state_q <= ST_CARRY_WRITE;
            end
          end
          ST_PAYLOAD_PREFIX: begin
            if (!tile_is_last_w && payload_prefix_index_q != 2'd3) begin
              payload_prefix_index_q <= payload_prefix_index_q + 2'd1;
            end else if (!tile_is_last_w) begin
              payload_len_q <= payload_len_q + 16'd4 + tile_len_q;
              tile_index_q <= tile_index_q + 16'd1;
              if (tile_col_q == (tile_cols_q - 16'd1)) begin
                tile_col_q <= 16'd0;
                tile_row_q <= tile_row_q + 16'd1;
              end else begin
                tile_col_q <= tile_col_q + 16'd1;
              end
              if (tile_col_q == (tile_cols_q - 16'd1)) begin
                tile_width_q <= (tile_cols_q == 16'd1) ? width_q : 16'd64;
                tile_height_q <=
                  ((tile_row_q + 16'd1) == (tile_rows_q - 16'd1)) ?
                    (height_q - ((tile_row_q + 16'd1) << 6)) : 16'd64;
              end else begin
                tile_width_q <=
                  ((tile_col_q + 16'd1) == (tile_cols_q - 16'd1)) ?
                    (width_q - ((tile_col_q + 16'd1) << 6)) : 16'd64;
                tile_height_q <= tile_height_q;
              end
              state_q <= ST_TILE_START;
            end else begin
              payload_len_q <= payload_len_q + tile_len_q;
              stream_index_q <= 16'd0;
              state_q <= ST_OUTPUT_PREP;
            end
          end
          ST_OUTPUT_PREP: begin
            // Header bytes are short and stay byte-serial. The staged tile
            // payload is read through a 16-bank RAM and handed to AXI in
            // aligned packets once stream_index_q reaches tile_payload_start_w.
            payload_read_word_addr_q <= 12'd0;
            output_last_q <= output_lookup_last_w;
            m_axis_valid <= 1'b1;
            m_axis_data <= {{(AXI_DATA_BITS - 8){1'b0}}, output_lookup_byte_w};
            m_axis_count <= OUTPUT_PACKET_COUNT_BITS'(1);
            m_axis_last <= output_lookup_last_w && frame_is_last_w;
            state_q <= ST_OUTPUT_VALID;
          end
          ST_OUTPUT_VALID: begin
            if (m_axis_valid && m_axis_ready) begin
              output_byte_phase_q <= output_next_byte_phase_w;
              if (output_last_q) begin
                m_axis_valid <= 1'b0;
                m_axis_count <= '0;
                m_axis_last <= 1'b0;
                stream_index_q <= 16'd0;
                if (frame_is_last_w) begin
                  state_q <= ST_IDLE;
                end else begin
                  frame_index_q <= frame_index_q + 32'd1;
                  input_frame_offset_q <= input_frame_offset_q + src_frame_stride;
                  seq_op_q <= 8'd0;
                  seq_bits_left_q <= 7'd0;
                  seq_value_q <= 64'd0;
                  seq_bit_pos_q <= 16'd0;
                  seq_len_q <= 16'd0;
                  payload_len_q <= 16'd0;
                  payload_prefix_index_q <= 2'd0;
                  low_q <= 64'd0;
                  rng_q <= 32'h8000;
                  cnt_q <= -8'sd9;
                  precarry_read_word_addr_q <= 12'd0;
                  pending_push_valid_q <= 1'b0;
                  pending_push_word_q <= 16'd0;
                  precarry_len_q <= 16'd0;
                  tile_len_q <= 16'd0;
                  tile_index_q <= 16'd0;
                  tile_col_q <= 16'd0;
                  tile_row_q <= 16'd0;
                  tile_width_q <= (tile_cols_q == 16'd1) ? width_q : 16'd64;
                  tile_height_q <= (tile_rows_q == 16'd1) ? height_q : 16'd64;
                  tile_input_index_q <= 32'd0;
                  tile_input_active_q <= 1'b0;
                  frame_palette_mode_q <= 1'b0;
                  frame_ibc_mode_q <= 1'b0;
                  phase_q <= PHASE_INTRA;
                  step_q <= 5'd0;
                  palette_row_q <= 6'd0;
                  palette_col_q <= 6'd0;
                  palette_identity_row_ctx_q <= 2'd3;
                  palette_mode_q <= 1'b0;
                  lossy_420_mode_q <= 1'b0;
                  leaf_luma_mode_q <= LUMA_MODE_DC;
                  leaf_chroma_bdpcm_horz_q <= 1'b1;
                  lossy420_luma_recon_q[0] <= 8'd128;
                  lossy420_luma_recon_q[1] <= 8'd128;
                  lossy420_luma_recon_q[2] <= 8'd128;
                  lossy420_luma_recon_q[3] <= 8'd128;
                  lossy420_luma_left_valid_q <= 16'd0;
                  lossy420_luma_above_valid_q <= 16'd0;
                  lossy420_u_left_valid_q <= 16'd0;
                  lossy420_v_left_valid_q <= 16'd0;
                  lossy420_u_above_valid_q <= 16'd0;
                  lossy420_v_above_valid_q <= 16'd0;
                  txb_index_q <= 16'd0;
                  txb_width_q <= 16'd0;
                  txb_count_q <= 16'd0;
                  txb_local_row_q <= 5'd0;
                  txb_local_col_q <= 5'd0;
                  txb_prefetch_started_q <= 1'b0;
                  txb_prefetch_done_q <= 1'b0;
                  txb_prefetch_chroma_q <= 1'b0;
                  txb_prefetch_plane_v_q <= 1'b0;
                  txb_prefetch_index_q <= 2'd0;
                  cached_v_valid_q <= 4'd0;
                  cached_chroma_samples_valid_q <= 4'd0;
                  left_edge_u_top_q <= 32'd0;
                  left_edge_u_bottom_q <= 32'd0;
                  left_edge_v_top_q <= 32'd0;
                  left_edge_v_bottom_q <= 32'd0;
                  left_edge_row_mi_q <= 5'd0;
                  left_edge_col_mi_q <= 5'd0;
                  left_edge_valid_q <= 1'b0;
                  above_col0_u_q <= 32'd0;
                  above_col0_v_q <= 32'd0;
                  above_col0_row_mi_q <= 5'd0;
                  above_col0_valid_q <= 1'b0;
                  last_u_txb_nonzero_q <= 1'b0;
                  block_row_mi_q <= 5'd0;
                  block_col_mi_q <= 5'd0;
                  block_w_mi_q <= 5'd16;
                  block_h_mi_q <= 5'd16;
                  partition_q <= PARTITION_NONE;
                  partition_emit_step_q <= 1'b0;
                  stack_sp_q <= 5'd0;
                  output_last_q <= 1'b0;
                  for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                    lossy420_luma_above_q[context_index_q] <= 8'd128;
                    lossy420_luma_left_top_q[context_index_q] <= 8'd128;
                    lossy420_luma_left_bottom_q[context_index_q] <= 8'd128;
                    lossy420_luma_left_col_mi_q[context_index_q] <= 5'd0;
                    lossy420_u_above_q[context_index_q] <= 8'd128;
                    lossy420_v_above_q[context_index_q] <= 8'd128;
                    lossy420_u_left_q[context_index_q] <= 8'd128;
                    lossy420_v_left_q[context_index_q] <= 8'd128;
                    lossy420_u_left_col_mi_q[context_index_q] <= 5'd0;
                    lossy420_v_left_col_mi_q[context_index_q] <= 5'd0;
                  end
                  state_q <= ST_TILE_START;
                end
              end else begin
                stream_index_q <= output_next_stream_index_w;
                if (output_next_stream_index_w >= tile_payload_start_w) begin
                  if (output_next_payload_word_addr_w == payload_read_data_word_addr_q) begin
                    output_last_q <= output_next_packet_last_w;
                    m_axis_valid <= 1'b1;
                    m_axis_data <= output_next_payload_packet_data_w;
                    m_axis_count <= output_next_payload_count_w;
                    m_axis_last <= output_next_packet_last_w && frame_is_last_w;
                    if (output_after_next_payload_w &&
                        (output_after_next_payload_word_addr_w != payload_read_data_word_addr_q)) begin
                      payload_read_word_addr_q <= output_after_next_payload_word_addr_w;
                    end
                    state_q <= ST_OUTPUT_VALID;
                  end else if (output_next_payload_word_addr_w == payload_read_word_addr_q) begin
                    m_axis_valid <= 1'b0;
                    m_axis_count <= '0;
                    m_axis_last <= 1'b0;
                    state_q <= ST_OUTPUT_PAYLOAD_LOAD;
                  end else begin
                    payload_read_word_addr_q <= output_next_payload_word_addr_w;
                    m_axis_valid <= 1'b0;
                    m_axis_count <= '0;
                    m_axis_last <= 1'b0;
                    state_q <= ST_OUTPUT_PAYLOAD_WAIT;
                  end
                end else begin
                  output_last_q <= output_lookup_last_w;
                  m_axis_valid <= 1'b1;
                  m_axis_data <= {{(AXI_DATA_BITS - 8){1'b0}}, output_lookup_byte_w};
                  m_axis_count <= OUTPUT_PACKET_COUNT_BITS'(1);
                  m_axis_last <= output_lookup_last_w && frame_is_last_w;
                  state_q <= ST_OUTPUT_VALID;
                end
              end
            end
          end
          ST_OUTPUT_PAYLOAD_WAIT: begin
            m_axis_valid <= 1'b0;
            m_axis_count <= '0;
            m_axis_last <= 1'b0;
            state_q <= ST_OUTPUT_PAYLOAD_LOAD;
          end
          ST_OUTPUT_PAYLOAD_LOAD: begin
            output_last_q <= output_current_packet_last_w;
            m_axis_valid <= 1'b1;
            m_axis_data <= output_payload_packet_data_w;
            m_axis_count <= output_payload_count_w;
            m_axis_last <= output_current_packet_last_w && frame_is_last_w;
            if (output_after_current_payload_w &&
                (output_after_current_payload_word_addr_w != payload_read_data_word_addr_q)) begin
              payload_read_word_addr_q <= output_after_current_payload_word_addr_w;
            end
            state_q <= ST_OUTPUT_VALID;
          end
          default: state_q <= ST_IDLE;
          endcase
        end
      end
    end
  end

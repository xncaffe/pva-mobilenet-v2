#ifdef USE_CUDNN
#include <vector>

#include "caffe/layers/cudnn_depthwise_convolution.hpp"

namespace caffe {

	__global__ void sync_depthwise_conv_groups() { }

	template <typename Dtype>
	void CuDNNDepthwiseConvolutionLayer<Dtype>::Forward_gpu(
		const vector<Blob<Dtype>*>& bottom, const vector<Blob<Dtype>*>& top) {
		//printf("##################################################### %d\r\n", top[0]->num());
		//printf("##################################################### %d\r\n", top[0]->channels());
		//printf("##################################################### %d\r\n", top[0]->height());
		//printf("##################################################### %d\r\n", top[0]->width());
		//printf("##################################################### %d\r\n", top[0]->gpu_data());
		//printf("##################################################### before cudnn depthwise\r\n");
		const Dtype* weight = this->blobs_[0]->gpu_data();
		for (int i = 0; i < bottom.size(); ++i) {
			const Dtype* bottom_data = bottom[i]->gpu_data();
			Dtype* top_data = top[i]->mutable_gpu_data();
            //printf("##################################################### test cudnn depthwise\r\n");
			// Forward through cuDNN in parallel over groups.
			//for (int g = 0; g < this->group_; g++) {
			{
				// Filters.
				CUDNN_CHECK(cudnnConvolutionForward(handle_,
					cudnn::dataType<Dtype>::one,
					bottom_descs_[i],
					bottom_data + bottom_offset_,
					filter_desc_,
					weight + this->weight_offset_,
					conv_descs_[i],
					fwd_algo_[i],
					workspace[0],
					workspace_fwd_sizes_[i],
					cudnn::dataType<Dtype>::zero,
					top_descs_[i], 
					top_data + top_offset_));				

				// Bias.
				if (this->bias_term_) {
					const Dtype* bias_data = this->blobs_[1]->gpu_data();
					CUDNN_CHECK(cudnnAddTensor(handle_,
						cudnn::dataType<Dtype>::one,
						bias_desc_, bias_data + bias_offset_,
						cudnn::dataType<Dtype>::one,
						top_descs_[i], top_data + top_offset_));
				}
			}

			// Synchronize the work across groups, each of which went into its own
			// stream, by launching an empty kernel into the default (null) stream.
			// NOLINT_NEXT_LINE(whitespace/operators)
			//sync_depthwise_conv_groups<<<1, 1>>>();
		}
		//printf("##################################################### after cudnn depthwise\r\n");
	}

	template <typename Dtype>
	void CuDNNDepthwiseConvolutionLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
		const vector<bool>& propagate_down, const vector<Blob<Dtype>*>& bottom) {
		const Dtype* weight = NULL;
		Dtype* weight_diff = NULL;
		if (this->param_propagate_down_[0]) {
			weight = this->blobs_[0]->gpu_data();
			weight_diff = this->blobs_[0]->mutable_gpu_diff();
		}
		Dtype* bias_diff = NULL;
		if (this->bias_term_ && this->param_propagate_down_[1]) {
			bias_diff = this->blobs_[1]->mutable_gpu_diff();
		}
		for (int i = 0; i < top.size(); ++i) {
			const Dtype* top_diff = top[i]->gpu_diff();
			// Backward through cuDNN in parallel over groups and gradients.
			//for (int g = 0; g < this->group_; g++) {
			{
				// Gradient w.r.t. bias.
				if (this->bias_term_ && this->param_propagate_down_[1]) {
					CUDNN_CHECK(cudnnConvolutionBackwardBias(handle_,
						cudnn::dataType<Dtype>::one,
						top_descs_[i], top_diff + top_offset_,
						cudnn::dataType<Dtype>::one,
						bias_desc_, bias_diff + bias_offset_));
				}

				// Gradient w.r.t. weights.
				if (this->param_propagate_down_[0]) {
					const Dtype* bottom_data = bottom[i]->gpu_data();
					CUDNN_CHECK(cudnnConvolutionBackwardFilter(
						handle_,
						cudnn::dataType<Dtype>::one,
						bottom_descs_[i], bottom_data + bottom_offset_,
						top_descs_[i], top_diff + top_offset_,
						conv_descs_[i],
						bwd_filter_algo_[i], workspace[0],
						workspace_bwd_filter_sizes_[i],
						cudnn::dataType<Dtype>::one,
						filter_desc_, weight_diff + this->weight_offset_));
				}

				// Gradient w.r.t. bottom data.
				if (propagate_down[i]) {
					if (weight == NULL) {
						weight = this->blobs_[0]->gpu_data();
					}
					Dtype* bottom_diff = bottom[i]->mutable_gpu_diff();
					CUDNN_CHECK(cudnnConvolutionBackwardData(
						handle_,
						cudnn::dataType<Dtype>::one,
						filter_desc_, weight + this->weight_offset_,
						top_descs_[i], top_diff + top_offset_,
						conv_descs_[i],
						bwd_data_algo_[i], workspace[0],
						workspace_bwd_data_sizes_[i],
						cudnn::dataType<Dtype>::zero,
						bottom_descs_[i], bottom_diff + bottom_offset_));
				}
			}

			// Synchronize the work across groups, each of which went into its own
			// stream, by launching an empty kernel into the default (null) stream.
			// NOLINT_NEXT_LINE(whitespace/operators)
			//sync_conv_groups << <1, 1 >> >();
		}
	}

	INSTANTIATE_LAYER_GPU_FUNCS(CuDNNDepthwiseConvolutionLayer);

}  // namespace caffe
#endif


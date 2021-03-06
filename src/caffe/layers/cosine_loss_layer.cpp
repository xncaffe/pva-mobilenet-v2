#include "caffe/layers/cosine_loss_layer.hpp"

namespace caffe {
	
	#define GET_INDEX(index, count)            \
	({                                         \
	   int add_shift = index * count + index;  \
	   add_shift;                              \
    }) 	   
	   

	template <typename Dtype>
	void CosineLossLayer<Dtype>::LayerSetUp(const vector<Blob<Dtype>*>& bottom,
		const vector<Blob<Dtype>*>& top) {
		LossLayer<Dtype>::LayerSetUp(bottom, top);
		CosineLossParameter cosine_loss_param = this->layer_param_.cosine_loss_param();
		pos_weight = cosine_loss_param.has_position_weight() ? cosine_loss_param.position_weight() : Dtype(1.0);
		nos_weight = cosine_loss_param.has_negative_weight() ? cosine_loss_param.negative_weight() : Dtype(1.0);
	}

	template <typename Dtype>
	void CosineLossLayer<Dtype>::Reshape(const vector<Blob<Dtype>*>& bottom,
		const vector<Blob<Dtype>*>& top) {
		LossLayer<Dtype>::Reshape(bottom, top);
		int batch = bottom[0]->num();
		vector<int> norm_shape;
		norm_shape.push_back(batch);
		//norm_.Reshape(norm_shape);
		norm_shape.push_back(batch);
		inner_product.Reshape(norm_shape);
	}

	template <typename Dtype>
	void CosineLossLayer<Dtype>::Forward_cpu(const vector<Blob<Dtype>*>& bottom,
		const vector<Blob<Dtype>*>& top) {
		int batch = bottom[0]->num();
		int channels = bottom[0]->channels();
		//int height = bottom[0]->height();
		//int width = bottom[0]->width();
        
		const Dtype *bottom_data = bottom[0]->cpu_data();
		//Dtype *norm_data = norm_.mutable_cpu_data();
		Dtype *inner_product_data = inner_product.mutable_cpu_data();
		Dtype loss = Dtype(0.0);
		const Dtype* label = bottom[1]->cpu_data();
        //caffe_set(norm_.count(), Dtype(0.0), norm_data);
		//for (size_t i = 0; i < batch; i++) {
		//	norm_data[i] = caffe_cpu_l2norm(channels, bottom_data + i * channels);
		//}

		caffe_cpu_gemm(CblasNoTrans, CblasTrans, batch, batch, channels, Dtype(1.0), 
			bottom_data, bottom_data, Dtype(0.0), inner_product_data);
		for (size_t i = 0; i < batch; i++) {
			for (size_t j = 0; j < batch; j++) {
				if (i == j) {
					continue;
				}
				//inner_product_data[i * batch + j] = caffe_cpu_dot(channels, bottom_data + i * channels, bottom_data + j * channels);
				int i_norm_index = GET_INDEX(i, batch); //i * batch + i;
				int j_norm_index = GET_INDEX(j, batch); //j * batch + j;
				Dtype norm_mul = inner_product_data[i_norm_index]* inner_product_data[j_norm_index];
				norm_mul = norm_mul < 0.01 ? 0.01 : norm_mul;
				inner_product_data[i * batch + j] /=  norm_mul;
				//LOG(INFO) << "############################ " << inner_product_data[i * batch + j];
				if (label[i] == label[j]) {
					loss += (1 - inner_product_data[i * batch + j]);
				}
				else {
					loss += inner_product_data[i * batch + j];
				}
			}
		}
		
		top[0]->mutable_cpu_data()[0] = loss / (batch - 1) / (batch - 1);

	}

	template <typename Dtype>
	void CosineLossLayer<Dtype>::Backward_cpu(const vector<Blob<Dtype>*>& top,
		const vector<bool>& propagate_down, const vector<Blob<Dtype>*>& bottom) {

		int batch = bottom[0]->num();
		int channels = bottom[0]->channels();
		//int height = bottom[0]->height();
		//int width = bottom[0]->width();
		const Dtype* label = bottom[1]->cpu_data();
		//const Dtype *norm_data = norm_.cpu_data();
		const Dtype *bottom_data = bottom[0]->mutable_cpu_data();		
        Dtype *inner_product_data = inner_product.mutable_cpu_data();
		
		if (propagate_down[0]) {

			Dtype* bottom_diff = bottom[0]->mutable_cpu_diff();
			caffe_set(bottom[0]->count(), Dtype(0.0), bottom_diff);

			for (size_t i = 0; i < batch; i++) {
				for (size_t j = 0; j < batch; j++) {
					if (i == j) {
						continue;
					}
					else {
						bool reverse = (label[i] == label[j]);
						accu_assign(batch, channels, reverse, bottom_data + j * channels, 
						bottom_diff + i * channels, inner_product_data[GET_INDEX(i, batch)]);
					}
				}
			}
		}

	}

#ifdef CPU_ONLY
	STUB_GPU(CosineLossLayer);
#endif

	INSTANTIATE_CLASS(CosineLossLayer);
	REGISTER_LAYER_CLASS(CosineLoss);

}